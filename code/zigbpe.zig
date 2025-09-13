const std = @import("std");
const SkippingList = @import("skipping_list").SkippingList;
const IndexedPriorityQueue = @import("indexed_priority_queue");

/// Helper function to incrementally update pair frequencies in the IPQ.
/// It handles adding, incrementing, and decrementing pair counts.
fn updateFrequency(
    ipq: *IndexedPriorityQueue.IndexedPriorityQueue(Pair, usize, void, maxHeapComparator),
    pair: Pair,
    delta: i64,
) !void {
    const entry = ipq.get(pair);
    if (entry) |e| {
        // The pair already exists in the queue, so we'll modify its value.
        const freq: i64 = @intCast(e.value);
        const new_freq: i64 = freq + delta;

        if (new_freq > 0) {
            _ = try ipq.changeValue(pair, @intCast(new_freq));
        } else {
            // NOTE: The provided IPQ API lacks a 'remove' function. Ideally, a pair
            // whose frequency drops to zero should be removed. We'll set its frequency
            // to 0, which should cause it to sink in the max-heap and not be selected.
            _ = try ipq.changeValue(pair, 0);
        }
    } else if (delta > 0) {
        // The pair is new and we're adding it (e.g., creating (P, Z)).
        _ = try ipq.push(pair, @intCast(delta));
    }
    // If the pair doesn't exist and delta is negative, we do nothing, which is correct.
}

/// Iterates through the list, merges all occurrences of the pair (left, right) into
/// a new `replacement` token, and incrementally updates the pair frequency queue.
fn mergePairs(
    comptime T: type,
    comptime skip_bits: u4,
    list: *SkippingList(T, skip_bits),
    ipq: *IndexedPriorityQueue.IndexedPriorityQueue(Pair, usize, void, maxHeapComparator),
    left: T,
    right: T,
    replacement: T,
) !void {
    var it = list.iterator();
    var prev_val: ?T = null;

    // We iterate manually to correctly update `prev_val` after a merge occurs.
    while (it.next()) |current_val| {
        // Peek at the next token to see if it forms our target pair.
        const next_val_opt = it.peek();

        if (next_val_opt) |next_val| {
            if (current_val == left and next_val == right) {
                // Match found! Sequence: (prev_val?, current_val, next_val, ...)

                // 1. Decrement frequency of the pair on the left: (prev_val, left)
                if (prev_val) |pv| {
                    try updateFrequency(ipq, Pair.init(pv, left), -1);
                }

                // 2. Perform the merge. This replaces `current_val` with `replacement`
                // and removes `next_val`. The iterator is now at the `replacement` node.
                it.replaceAndSkipNext(replacement);

                // 3. Get the token that followed the original pair.
                const next_next_val = it.peek();

                // 4. Update frequencies for right-side and newly created pairs.
                if (next_next_val) |nnv| {
                    // Decrement the old pair on the right: (right, next_next_val)
                    try updateFrequency(ipq, Pair.init(right, nnv), -1);
                    // Increment the new pair on the right: (replacement, next_next_val)
                    try updateFrequency(ipq, Pair.init(replacement, nnv), 1);
                }
                if (prev_val) |pv| {
                    // Increment the new pair on the left: (prev_val, replacement)
                    try updateFrequency(ipq, Pair.init(pv, replacement), 1);
                }

                // 5. The new `replacement` token is now the "previous" token for the next iteration.
                prev_val = replacement;

            } else {
                // No match, just advance prev_val normally.
                prev_val = current_val;
            }
        } else {
            // Reached the end of the list.
            prev_val = current_val;
        }
    }
}

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

fn maxHeapComparator(_: void, a: usize, b: usize) bool {
    return a > b;
}

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

    const start_time = std.time.nanoTimestamp();

    // Key - pair
    // Value - frequency
    const IntIntMaxIPQ = IndexedPriorityQueue.IndexedPriorityQueue(Pair, usize, void, maxHeapComparator);

    // Create an instance of the IPQ.
    var ipq = IntIntMaxIPQ.init(allocator, {});
    defer ipq.deinit();

    while (current_token < target_token_size) {

        // When there's only one pair or less we cannot continue
        if(list.get_size() < 2) {
            break;
        }
        
        // When the ipq is empty it means we need to do a full iteration and count the frequencies
        if(ipq.isEmpty()) {
            try stdout.print("Initial count\n", .{});
            var it = list.iterator();
            while (true) {
                // Get the current and next tokens
                const this_token = it.next();
                if (this_token == null) break;
                const next_token = it.peek();
                if (next_token == null) break;

                const pair = Pair.init(this_token.?, next_token.?);
                const freq_entry = ipq.get(pair);

                if (freq_entry) |entry| {
                    _ = try ipq.changeValue(pair, entry.value + 1);
                } else {
                    _ = try ipq.push(pair, 1);
                }
            }
        }

        // Get the most frequent pair
        const most_frequent = try ipq.pop();
        const most_frequent_pair = most_frequent.key;

        // do the replacement and modify the ipq as we go
        mergePairs(TokenType, SkipBits, &list, &ipq, most_frequent_pair.first, most_frequent_pair.second, current_token) catch {
            try stdout.print("Error during merging pairs\n", .{});
            break;
        };

        // debug print the most frequent pair
        try stdout.print("Most frequent pair so far: ({d}, {d}) with frequency {d}\n", .{ most_frequent_pair.first, most_frequent_pair.second, most_frequent.value });
        current_token += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_nanoseconds = end_time - start_time;
    std.debug.print("Total time elapsed: {} ms\n", .{@divTrunc(elapsed_nanoseconds ,std.time.ns_per_ms)});
    try stdout.print("File size: {d} bytes, SkippingList size: {d}\n", .{ file_size, list.get_size() });
}
