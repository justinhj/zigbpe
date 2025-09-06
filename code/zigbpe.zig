const std = @import("std");
const SkippingList = @import("skipping_list").SkippingList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file_path>\n", .{args[0]});
        return;
    }

    const file_path = args[1];
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    try file.seekTo(0);

    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.reader().readAll(contents);

    // Just an example of using the skipping list
    // We'll treat the file contents as a u32 array for this example
    const data_as_u32 = try allocator.alloc(u32, file_size);
    defer allocator.free(data_as_u32);

    for (contents, 0..) |b, i| {
        data_as_u32[i] = b;
    }

    var list = try SkippingList(u32, 8).init(allocator, data_as_u32);
    defer list.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });

    // Steps
    // 1. Set up the main loop with the target token size
    // 2. Loop over the data counting frequencies and keep the most frequent pair
    // 3. Replace the most frequent pair with a new token

    const target_token_size = 512;
    var current_token: usize = 256;
    var freqs = std.AutoHashMap(u32, []const u8).init(allocator);
    defer freqs.deinit();

    while (current_token < target_token_size) {
        current_token += 1;
    }
}
