// Manage pcre2 regex matching
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

compiled_pattern: ?*c.pcre2_code_8 = null,
allocator: Allocator,
allocator_wrapper: *Allocator,
general_context: ?*c.pcre2_general_context_8,
compile_context: ?*c.pcre2_compile_context_8,

const PCRE2_Matcher = @This();
const Self = @This();

const PCRE2_Errors = error{
    FailedToCompileRegex,
    JITCompilationFailed,
    OutOfMemory,
    MatchDataCreationFailure,
    MatchContextCreationFailure,
};

const HEADER_SIZE = @sizeOf(usize);

fn private_malloc(size: usize, memdata: ?*anyopaque) callconv(.c) ?*anyopaque {
    const allocator = @as(*std.mem.Allocator, @ptrCast(@alignCast(memdata.?)));
    const total_size = size + HEADER_SIZE;
    const alignment = comptime std.mem.Alignment.fromByteUnits(@alignOf(usize));

    const slice = allocator.alignedAlloc(u8, alignment, total_size) catch return null;
    // std.debug.print("private malloc allocated requested {d} actual {d} bytes at 0x{x}\n", .{ size, total_size, @intFromPtr(slice.ptr) });

    const header_ptr = @as(*usize, @ptrCast(slice.ptr));
    header_ptr.* = total_size;

    return slice.ptr + HEADER_SIZE;
}

fn private_free(ptr: ?*anyopaque, memdata: ?*anyopaque) callconv(.c) void {
    if (ptr == null) return {};

    const allocator = @as(*std.mem.Allocator, @ptrCast(@alignCast(memdata.?)));
    // std.debug.print("private free 0x{x}\n", .{@intFromPtr(ptr)});

    const data_ptr = @intFromPtr(ptr.?);
    const start_addr = data_ptr - HEADER_SIZE;
    const raw_ptr = @as([*]u8, @ptrFromInt(start_addr));

    const header_ptr = @as(*usize, @ptrCast(@alignCast(raw_ptr)));
    const total_size = header_ptr.*;

    const aligned_ptr = @as([*]align(@alignOf(usize)) u8, @ptrCast(@alignCast(raw_ptr)));
    const slice = aligned_ptr[0..total_size];

    allocator.free(slice);
    return {};
}

pub fn init(allocator: Allocator, regex: []const u8) PCRE2_Errors!PCRE2_Matcher {
    var error_number: c_int = 0;
    var error_offset: usize = 0;

    const allocator_wrapper = allocator.create(Allocator) catch return PCRE2_Errors.OutOfMemory;
    allocator_wrapper.* = allocator;
    errdefer allocator.destroy(allocator_wrapper);

    const pcre2_general_context = c.pcre2_general_context_create_8(
        private_malloc,
        private_free,
        @as(*usize, @ptrCast(@constCast(allocator_wrapper))),
    );

    const pcre2_compile_context = c.pcre2_compile_context_create_8(pcre2_general_context);
    if (pcre2_compile_context == null) return PCRE2_Errors.OutOfMemory;

    const pcre2_compiled_pattern = c.pcre2_compile_8(
        regex.ptr,
        regex.len,
        c.PCRE2_UTF,
        &error_number,
        &error_offset,
        pcre2_compile_context,
    );
    if (pcre2_compiled_pattern == null) {
        std.debug.print("PCRE2 compilation failed with error code {d} at offset {d}\n", .{ error_number, error_offset });
        return PCRE2_Errors.FailedToCompileRegex;
    }
    const jit_errorcode = c.pcre2_jit_compile_8(pcre2_compiled_pattern, c.PCRE2_JIT_COMPLETE);
    if (jit_errorcode < 0) {
        var buffer: [256]u8 = undefined;
        const error_message_len = c.pcre2_get_error_message_8(jit_errorcode, &buffer, buffer.len);
        if (error_message_len > 0) {
            std.debug.print("Warning: PCRE2 JIT compilation failed: {s}\n", .{buffer[0..@intCast(error_message_len)]});
        }
        return PCRE2_Errors.JITCompilationFailed;
    }
    return .{ .allocator = allocator, .allocator_wrapper = allocator_wrapper, .compiled_pattern = pcre2_compiled_pattern.?, .general_context = pcre2_general_context, .compile_context = pcre2_compile_context };
}

pub fn deinit(self: *Self) void {
    if (self.compiled_pattern) |p| {
        c.pcre2_code_free_8(p);
        self.compiled_pattern = null;
    }
    c.pcre2_compile_context_free_8(self.compile_context);
    c.pcre2_general_context_free_8(self.general_context);
    self.allocator.destroy(self.allocator_wrapper);
}

pub fn iterator(self: *const Self, subject: []const u8) PCRE2_Errors!Iterator {
    const match_data = c.pcre2_match_data_create_from_pattern_8(self.compiled_pattern, self.general_context);
    if (match_data == null) return PCRE2_Errors.MatchDataCreationFailure;

    const match_context = c.pcre2_match_context_create_8(self.general_context);
    if (match_context == null) {
        c.pcre2_match_data_free_8(match_data);
        return PCRE2_Errors.MatchContextCreationFailure;
    }

    return Iterator{
        .parent = self,
        .subject = subject,
        .match_data = match_data,
        .match_context = match_context,
    };
}

pub const Iterator = struct {
    parent: *const PCRE2_Matcher,
    subject: []const u8,
    match_data: ?*c.pcre2_match_data_8,
    match_context: ?*c.pcre2_match_context_8,
    current_offset: usize = 0,

    pub fn deinit(self: *Iterator) void {
        if (self.match_data) |md| c.pcre2_match_data_free_8(md);
        if (self.match_context) |mc| c.pcre2_match_context_free_8(mc);
        self.match_data = null;
        self.match_context = null;
    }

    pub fn next(self: *Iterator) !?[]const u8 {
        if (self.match_data == null) return null;

        const rc = c.pcre2_match_8(
            self.parent.compiled_pattern,
            self.subject.ptr,
            self.subject.len,
            self.current_offset,
            c.PCRE2_NO_UTF_CHECK,
            self.match_data,
            self.match_context,
        );

        if (rc == c.PCRE2_ERROR_NOMATCH) {
            return null;
        }

        if (rc < 0) {
            std.debug.print("PCRE2 matching error: {d}\n", .{rc});
            return error.Pcre2MatchError;
        }

        const ovector = c.pcre2_get_ovector_pointer_8(self.match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        const match = self.subject[match_start..match_end];
        self.current_offset = match_end;

        // prevent infinite loops
        if (match_end == match_start) {
            self.current_offset += 1;
            // Guard against going past EOF
            if (self.current_offset > self.subject.len) return null;
        }

        return match;
    }
};
