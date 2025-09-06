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
    const data_as_u32 = std.mem.bytesAsSlice(u32, contents);
    var list = try SkippingList(u32, 8).init(allocator, data_as_u32);
    defer list.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });
}
