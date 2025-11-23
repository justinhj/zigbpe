// Manage pcre2 regex matching
const std = @import("std");

pub const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

compiled_pattern: ?*c.pcre2_code_8,

const PCRE2_Matcher = @This();
const Self = @This();

const PCRE2_Errors = error {
    FailedToCompileRegex,
};

pub fn init(regex : []const u8) PCRE2_Errors!PCRE2_Matcher {
    var error_number: c_int = 0;
    var error_offset: usize = 0;

    const pcre2_compiled_pattern = c.pcre2_compile_8(
        regex.ptr,
        regex.len,
        0,
        &error_number,
        &error_offset,
        null,
    );
    if (pcre2_compiled_pattern == null) {
        std.debug.print("PCRE2 compilation failed with error code {d} at offset {d}\n", .{error_number, error_offset});
        return PCRE2_Errors.FailedToCompileRegex;
    }
    return .{
       .compiled_pattern = pcre2_compiled_pattern.?
    };
}

pub fn deinit(self: *Self) void {
    c.pcre2_code_free_8(self.compiled_pattern);
}
