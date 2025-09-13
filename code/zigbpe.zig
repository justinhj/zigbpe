const std = @import("std");
// No longer needed: const SkippingList = @import("skipping_list").SkippingList;
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
    list: *std.DoublyLinkedList(T),
    allocator: std.mem.Allocator,
    ipq: *IndexedPriorityQueue.IndexedPriorityQueue(Pair, usize, void, maxHeapComparator),
    left: T,
    right: T,
    replacement: T,
) !void {
    var prev_node: ?*std.DoublyLinkedList(T).Node = null;
    var current_node = list.first;

    while (current_node) |node| {
        // Peek at the next node to see if it forms our target pair.
        const next_node_opt = node.next;

        if (next_node_opt) |next_node| {
            if (node.data == left and next_node.data == right) {
                // Match found! Sequence: (prev_node?, node, next_node, ...)

                // 1. Decrement frequency of the pair on the left: (prev_node.data, left)
                if (prev_node) |pn| {
                    try updateFrequency(ipq, Pair.init(pn.data, left), -1);
                }

                // 2. Perform the merge. This replaces `node.data` with `replacement`
                // and removes `next_node`.
                const node_to_remove = next_node;
                const next_next_node = node_to_remove.next;

                // Remove and free the next node
                list.remove(node_to_remove);
                allocator.destroy(node_to_remove);

                // Replace the data in the current node
                node.data = replacement;

                // 3. & 4. Update frequencies for right-side and newly created pairs.
                if (next_next_node) |nnn| {
                    // Decrement the old pair on the right: (right, next_next_node.data)
                    try updateFrequency(ipq, Pair.init(right, nnn.data), -1);
                    // Increment the new pair on the right: (replacement, next_next_node.data)
                    try updateFrequency(ipq, Pair.init(replacement, nnn.data), 1);
                }
                if (prev_node) |pn| {
                    // Increment the new pair on the left: (prev_node.data, replacement)
                    try updateFrequency(ipq, Pair.init(pn.data, replacement), 1);
                }

                // 5. The current `node` (now containing `replacement`) is the "previous"
                // node for the next iteration.
                prev_node = node;
                current_node = next_next_node; // Move iterator to the node after the removed one
            } else {
                // No match, just advance normally.
                prev_node = node;
                current_node = node.next;
            }
        } else {
            // Reached the end of the list. No more pairs to check.
            current_node = null;
        }
    }
}

const TokenType = u32;
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

    var list = std.DoublyLinkedList(TokenType){};
    // Defer freeing all nodes that were allocated for the list.
    defer {
        while (list.popFirst()) |node| {
            allocator.destroy(node);
        }
    }

    // Manually create nodes and append them to the list.
    for (data_as_u32) |token| {
        const node = try allocator.create(std.DoublyLinkedList(TokenType).Node);
        node.* = .{ .data = token };
        list.append(node);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("File size: {d} bytes, DoublyLinkedList size: {d}\n", .{ file_size, list.len });

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
        if (list.len < 2) {
            break;
        }

        // When the ipq is empty it means we need to do a full iteration and count the frequencies
        if (ipq.isEmpty()) {
            try stdout.print("Initial count\n", .{});
            var current_node = list.first;
            while (current_node) |node| {
                // Get the current and next tokens by looking at the next node
                if (node.next) |next_node| {
                    const pair = Pair.init(node.data, next_node.data);
                    const freq_entry = ipq.get(pair);

                    if (freq_entry) |entry| {
                        _ = try ipq.changeValue(pair, entry.value + 1);
                    } else {
                        _ = try ipq.push(pair, 1);
                    }
                }
                current_node = node.next;
            }
        }

        // Get the most frequent pair
        const most_frequent = try ipq.pop();
        const most_frequent_pair = most_frequent.key;

        // do the replacement and modify the ipq as we go
        mergePairs(TokenType, &list, allocator, &ipq, most_frequent_pair.first, most_frequent_pair.second, current_token) catch {
            try stdout.print("Error during merging pairs\n", .{});
            break;
        };

        // debug print the most frequent pair
        try stdout.print("Most frequent pair so far: ({d}, {d}) with frequency {d}\n", .{ most_frequent_pair.first, most_frequent_pair.second, most_frequent.value });
        current_token += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_nanoseconds = end_time - start_time;
    std.debug.print("Total time elapsed: {} ms\n", .{@divTrunc(elapsed_nanoseconds, std.time.ns_per_ms)});
    try stdout.print("File size: {d} bytes, DoublyLinkedList size: {d}\n", .{ file_size, list.len });
}
