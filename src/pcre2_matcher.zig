// Manage pcre2 regex matching
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

compiled_pattern: ?*c.pcre2_code_8 = null,
allocator: Allocator,
general_context: ?*c.pcre2_general_context_8,

const PCRE2_Matcher = @This();
const Self = @This();

const PCRE2_Errors = error{
    FailedToCompileRegex,
    JITCompilationFailed,
};

fn private_malloc(size: usize, memdata: ?*anyopaque) callconv(.c) ?*anyopaque {
    const allocator = @as(*std.mem.Allocator, @ptrCast(@alignCast(memdata.?)));
    const slice = allocator.alignedAlloc(u8, @alignOf(usize), size) catch return null;
    std.debug.print("private malloc allocated {d} bytes at 0x{x}\n", .{size, slice.ptr});
    return @as(*usize, @ptrCast(slice.ptr));
}

fn private_free(memory: ?*anyopaque, memdata: ?*anyopaque) callconv(.c) void {
    const allocator = @as(*std.mem.Allocator, @ptrCast(@alignCast(memdata.?)));
    std.debug.print("private free 0x{x}\n", .{@intFromPtr(memory)});
    return allocator.free(memory);
}

pub fn init(allocator: Allocator, regex: []const u8) PCRE2_Errors!PCRE2_Matcher {
    var error_number: c_int = 0;
    var error_offset: usize = 0;

    const pcre2_general_context = c.pcre2_general_context_create_8(
            private_malloc,
            private_free,
            @as(*usize, @ptrCast(@constCast(&allocator))),
        );

    const pcre2_compiled_pattern = c.pcre2_compile_8(
        regex.ptr,
        regex.len,
        c.PCRE2_UTF,
        &error_number,
        &error_offset,
        pcre2_general_context,
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
    return .{ .allocator = allocator, .compiled_pattern = pcre2_compiled_pattern.?, .general_context = null };
}

pub fn deinit(self: *Self) void {
    if (self.compiled_pattern) |p| {
        c.pcre2_code_free_8(p);
        self.compiled_pattern = null;
    }
}
