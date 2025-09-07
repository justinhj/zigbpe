const std = @import("std");
const SkippingList = @import("skipping_list").SkippingList;
const binaryHeap = @import("binaryheap");
const ArrayList = std.ArrayList;

fn mergePairs(
    comptime T: type,
    comptime skip_bits: u4,
    list: *SkippingList(T, skip_bits),
    left: T,
    right: T,
    replacement: T,
) !void {
    var it = list.iterator();
    while (it.next()) |current_val| {
        const next_val = it.peek() orelse break;

        if (current_val == left and next_val == right) {
            it.replaceAndSkipNext(replacement);
        }
    }
}

pub fn main() !void {
    const TokenType = u32;
    const SkipBits = 8;
    const Pair = struct {
        first: TokenType,
        second: TokenType,

        pub fn init(f: TokenType, s: TokenType) @This() {
            return @This(){
                .first = f,
                .second = s,
            };
        }
    };

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

    var list = try SkippingList(u32, SkipBits).init(allocator, data_as_u32);
    defer list.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });

    // Steps
    // 1. Set up the main loop with the target token size
    // 2. Loop over the data counting frequencies and keep the most frequent pair
    // 3. Replace the most frequent pair with a new token

    const target_token_size = 512;
    var current_token: TokenType = 256;

    // Priority queue for tracking most frequent pairs
    const PairCount = struct {
        pair: Pair,
        count: usize,
    };

    const ComparePairCount = struct {
        pub fn lessThan(a: PairCount, b: PairCount) bool {
            if (a.count != b.count) {
                return a.count > b.count;
            }
            if (a.pair.first != b.pair.first) {
                return a.pair.first > b.pair.first;
            }
            return a.pair.second > b.pair.second;
        }
    };

    var priority_queue = try binaryHeap.BinaryHeap(PairCount).initCapacity(allocator, file_size, ComparePairCount.lessThan);
    defer priority_queue.deinit();

    // Hold all the tokens for output at the end
    var tokens = try ArrayList(Pair).initCapacity(allocator, target_token_size);
    defer tokens.deinit();

    // HashMap for tracking pair frequencies
    var freqs = std.AutoHashMap(Pair, usize).init(allocator);
    defer freqs.deinit();

    const start_time = std.time.nanoTimestamp();

    // Step 1: Count all pairs at the start
    var it = list.iterator();
    while (true) {
        const this_token = it.next();
        if (this_token == null) break;
        const next_token = it.peek();
        if (next_token == null) break;

        const pair = Pair.init(this_token.?, next_token.?);
        const freq_entry = freqs.get(pair);
        if (freq_entry) |entry| {
            try freqs.put(pair, entry + 1);
        } else {
            try freqs.put(pair, 1);
        }
    }

    // Step 2: Populate priority queue with initial frequencies
    var freq_iter = freqs.iterator();
    while (freq_iter.next()) |entry| {
        _ = try priority_queue.insert(.{ .pair = entry.key_ptr.*, .count = entry.value_ptr.* });
    }

    // Step 3: Main loop - process most frequent pairs
    while (current_token < target_token_size and priority_queue.count() > 0) {
        const extract_min = priority_queue.extractMin();
        if (extract_min == null) break;

        const pair_to_merge = extract_min.?.min_value.pair;

        // Skip if this pair no longer exists (was merged)
        if (freqs.get(pair_to_merge)) |count| {
            if (count == 0) continue;

            // Do the replacement
            mergePairs(TokenType, SkipBits, &list, pair_to_merge.first, pair_to_merge.second, current_token) catch {
                try stdout.print("Error during merging pairs\n", .{});
                break;
            };

            try tokens.append(pair_to_merge);

            // Update frequencies after merging
            // This is a simplified approach - in practice, we'd need to recalculate affected pairs
            try freqs.put(extract_min.?.min_value.pair, 0); // Mark as merged

            try stdout.print("Merged pair: ({d}, {d}) with frequency {d}\n", .{ pair_to_merge.first, pair_to_merge.second, extract_min.?.min_value.count });
            current_token += 1;
        }
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_nanoseconds = end_time - start_time;
    std.debug.print("Total time elapsed: {} ms\n", .{@divTrunc(elapsed_nanoseconds, std.time.ns_per_ms)});
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });
}
