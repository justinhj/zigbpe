const std = @import("std");
const SkippingList = @import("skipping_list").SkippingList;
const binaryHeap = @import("binaryheap");

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

    const data_as_u32 = try allocator.alloc(u32, file_size);
    defer allocator.free(data_as_u32);

    for (contents, 0..) |b, i| {
        data_as_u32[i] = b;
    }

    var list = try SkippingList(u32, SkipBits).init(allocator, data_as_u32);
    defer list.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });

    const target_token_size = 512;
    var current_token: TokenType = 256;

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

    var pair_to_index = std.AutoHashMap(Pair, usize).init(allocator);
    defer pair_to_index.deinit();

    var freqs = std.AutoHashMap(Pair, usize).init(allocator);
    defer freqs.deinit();

    const start_time = std.time.nanoTimestamp();

    var it = list.iterator();
    while (true) {
        const this_token = it.next() orelse break;
        const next_token = it.peek() orelse break;
        const pair = Pair.init(this_token, next_token);
        const count = freqs.get(pair) orelse 0;
        try freqs.put(pair, count + 1);
    }

    var freq_iter = freqs.iterator();
    while (freq_iter.next()) |entry| {
        const pair = entry.key_ptr.*;
        const count = entry.value_ptr.*;
        const index = try priority_queue.insert(.{ .pair = pair, .count = count });
        try pair_to_index.put(pair, index);
    }

    while (current_token < target_token_size) {
        var top_pair_count: ?PairCount = null;

        while (priority_queue.count() > 0) {
            const peeked_pair = priority_queue.peekMin().?;
            const real_freq = freqs.get(peeked_pair.pair) orelse 0;

            if (peeked_pair.count == real_freq and real_freq > 0) {
                top_pair_count = peeked_pair;
                break;
            } else {
                const extracted = priority_queue.extractMin().?;
                _ = pair_to_index.remove(extracted.min_value.pair);
                if (extracted.moved_element) |moved| {
                    try pair_to_index.put(moved.value.pair, moved.new_index);
                }
            }
        }

        if (top_pair_count == null) break;

        const extracted = priority_queue.extractMin().?;
        const pair_to_merge = extracted.min_value.pair;
        _ = pair_to_index.remove(pair_to_merge);
        if (extracted.moved_element) |moved| {
            try pair_to_index.put(moved.value.pair, moved.new_index);
        }

        try stdout.print("Merged pair: ({d}, {d}) with frequency {d}\n", .{ pair_to_merge.first, pair_to_merge.second, extracted.min_value.count });

        freqs.clearRetainingCapacity();
        var list_it = list.iterator();
        while (list_it.next()) |current_val| {
            const next_val = list_it.peek() orelse break;
            if (current_val == pair_to_merge.first and next_val == pair_to_merge.second) {
                list_it.replaceAndSkipNext(current_token);
            } else {
                const pair = Pair.init(current_val, next_val);
                const count = freqs.get(pair) orelse 0;
                try freqs.put(pair, count + 1);
            }
        }

        var pq_it = freqs.iterator();
        while (pq_it.next()) |entry| {
            const pair = entry.key_ptr.*;
            const count = entry.value_ptr.*;
            if (pair_to_index.get(pair)) |index| {
                const new_index = priority_queue.modify(index, .{ .pair = pair, .count = count });
                try pair_to_index.put(pair, new_index);
            } else {
                const new_index = try priority_queue.insert(.{ .pair = pair, .count = count });
                try pair_to_index.put(pair, new_index);
            }
        }

        current_token += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_nanoseconds = end_time - start_time;
    std.debug.print("Total time elapsed: {} ms\n", .{@divTrunc(elapsed_nanoseconds, std.time.ns_per_ms)});
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });
}