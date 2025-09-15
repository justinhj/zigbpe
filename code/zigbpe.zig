const std = @import("std");
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
    pair_occurrences: *std.AutoHashMap(Pair, std.AutoHashMap(*Node, void)),
    left: T,
    right: T,
    replacement: T,
) !void {
    const pair_to_merge = Pair.init(left, right);
    const locations_map = pair_occurrences.get(pair_to_merge) orelse return;

    var locations_to_process = std.ArrayList(*Node).init(allocator);
    defer locations_to_process.deinit();
    var iter = locations_map.keyIterator();
    while (iter.next()) |node_ptr| {
        try locations_to_process.append(node_ptr.*);
    }

    for (locations_to_process.items) |node| {
        if (node.next == null or node.data != left or node.next.?.data != right) {
            continue;
        }

        const prev_node = node.prev;
        const next_node = node.next.?;
        const next_next_node = next_node.next;

        // 1. Update destroyed pairs
        if (prev_node) |pn| {
            const old_pair = Pair.init(pn.data, left);
            try updateFrequency(ipq, old_pair, -1);
            if (pair_occurrences.getPtr(old_pair)) |loc_map| {
                _ = loc_map.remove(pn);
            }
        }
        if (next_next_node) |nnn| {
            const old_pair = Pair.init(right, nnn.data);
            try updateFrequency(ipq, old_pair, -1);
            if (pair_occurrences.getPtr(old_pair)) |loc_map| {
                _ = loc_map.remove(next_node);
            }
        }

        // 2. Merge
        node.data = replacement;
        list.remove(next_node);
        allocator.destroy(next_node);

        // 3. Update created pairs
        if (prev_node) |pn| {
            const new_pair = Pair.init(pn.data, replacement);
            try updateFrequency(ipq, new_pair, 1);
            const locations_map_ptr = pair_occurrences.getPtr(new_pair);
            if (locations_map_ptr) |loc_map| {
                try loc_map.put(pn, {});
            } else {
                var new_loc_map = std.AutoHashMap(*Node, void).init(allocator);
                errdefer new_loc_map.deinit();
                try new_loc_map.put(pn, {});
                try pair_occurrences.put(new_pair, new_loc_map);
            }
        }
        if (next_next_node) |nnn| {
            const new_pair = Pair.init(replacement, nnn.data);
            try updateFrequency(ipq, new_pair, 1);
            const locations_map_ptr = pair_occurrences.getPtr(new_pair);
            if (locations_map_ptr) |loc_map| {
                try loc_map.put(node, {});
            } else {
                var new_loc_map = std.AutoHashMap(*Node, void).init(allocator);
                errdefer new_loc_map.deinit();
                try new_loc_map.put(node, {});
                try pair_occurrences.put(new_pair, new_loc_map);
            }
        }
    }

    // 4. Remove merged pair from occurrences map
    if (pair_occurrences.getPtr(pair_to_merge)) |loc_map| {
        loc_map.deinit();
    }
    _ = pair_occurrences.remove(pair_to_merge);
}

const TokenType = u32;
const Node = std.DoublyLinkedList(TokenType).Node;

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
 // 1. Create a backing allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const backing_allocator = gpa.allocator();

    // 2. Create the Arena and its state
    var arena_state = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena_state.deinit();
    
    // 3. This is the allocator you will now use for all nodes and temporary allocations
    const allocator = arena_state.allocator();

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

    const PairOccurrencesMap = std.AutoHashMap(Pair, std.AutoHashMap(*Node, void));
    var pair_occurrences = PairOccurrencesMap.init(allocator);
    defer {
        // We need to deinit the inner hashmaps too
        var it = pair_occurrences.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        pair_occurrences.deinit();
    }

    while (current_token < target_token_size) {
        const step_start_time = std.time.nanoTimestamp();
        // When there's only one pair or less we cannot continue
        if (list.len < 2) {
            break;
        }

        // When the ipq is empty it means we need to do a full iteration and count the frequencies
        if (ipq.isEmpty()) {
            const initial_count_start_time = std.time.nanoTimestamp();
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

                    // Also update the pair_occurrences map
                    const locations_map_ptr = pair_occurrences.getPtr(pair);
                    if (locations_map_ptr) |loc_map| {
                        try loc_map.put(node, {});
                    } else {
                        var new_loc_map = std.AutoHashMap(*Node, void).init(allocator);
                        try new_loc_map.put(node, {});
                        try pair_occurrences.put(pair, new_loc_map);
                    }
                }
                current_node = node.next;
            }
            const initial_count_end_time = std.time.nanoTimestamp();
            const initial_count_elapsed_nanoseconds = initial_count_end_time - initial_count_start_time;
            try stdout.print("Initial count time elapsed: {} ms\n", .{@divTrunc(initial_count_elapsed_nanoseconds, std.time.ns_per_ms)});
        }

        // Get the most frequent pair
        const most_frequent = try ipq.pop();
        const most_frequent_pair = most_frequent.key;

        // do the replacement and modify the ipq as we go
        mergePairs(TokenType, &list, allocator, &ipq, &pair_occurrences, most_frequent_pair.first, most_frequent_pair.second, current_token) catch {
            try stdout.print("Error during merging pairs\n", .{});
            break;
        };

        // debug print the most frequent pair
        try stdout.print("Most frequent pair so far: ({d}, {d}) with frequency {d}\n", .{ most_frequent_pair.first, most_frequent_pair.second, most_frequent.value });
        current_token += 1;

        const step_end_time = std.time.nanoTimestamp();
        const step_elapsed_nanoseconds = step_end_time - step_start_time;
        try stdout.print("Step time elapsed: {} ms\n", .{@divTrunc(step_elapsed_nanoseconds, std.time.ns_per_ms)});
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_nanoseconds = end_time - start_time;
    std.debug.print("Total time elapsed: {} ms\n", .{@divTrunc(elapsed_nanoseconds, std.time.ns_per_ms)});
    try stdout.print("File size: {d} bytes, DoublyLinkedList size: {d}\n", .{ file_size, list.len });
}
