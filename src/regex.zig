const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const IndexedPriorityQueue = @import("indexed_priority_queue");

const pcre2_matcher = @import("pcre2_matcher.zig");
const c = pcre2_matcher.c;

// GPT-2 Pattern
const GPT2_SPLIT_PATTERN: []const u8 =
    \\'(?:[sdmt]|ll|ve|re)| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+
;

// GPT-4 Pattern
const GPT4_SPLIT_PATTERN: []const u8 =
    \\'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]++[\r\n]*|\s*[\r\n]|\s+(?!\S)|\s+
;

// Type to use for our DL list of nodes
const N = struct {
    data: u32,
    node: std.DoublyLinkedList.Node,
};

/// Helper function to incrementally update pair frequencies in the IPQ.
/// It handles adding, incrementing, and decrementing pair counts.
fn updateFrequency(
    allocator: std.mem.Allocator,
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
        _ = try ipq.push(allocator, pair, @intCast(delta));
    }
    // If the pair doesn't exist and delta is negative, we do nothing, which is correct.
}

/// Iterates through the list, merges all occurrences of the pair (left, right) into
/// a new `replacement` token, and incrementally updates the pair frequency queue.
fn mergePairs(
    comptime T: type,
    list: *std.DoublyLinkedList,
    allocator: std.mem.Allocator,
    ipq: *IndexedPriorityQueue.IndexedPriorityQueue(Pair, usize, void, maxHeapComparator),
    left: T,
    right: T,
    replacement: T,
) !void {
    var prev_node: ?*std.DoublyLinkedList.Node = null;
    var current_node = list.first;

    while (current_node) |dl_node| {
        const node: *N = @fieldParentPtr("node", dl_node);
        // Peek at the next node to see if it forms our target pair.
        const next_node_opt = dl_node.next;

        if (next_node_opt) |next_dl_node| {
            const next_node: *N = @fieldParentPtr("node", next_dl_node);
            if (node.data == left and next_node.data == right) {
                // Match found! Sequence: (prev_node?, node, next_node, ...)

                // 1. Decrement frequency of the pair on the left: (prev_node.data, left)
                if (prev_node) |dl_pn| {
                    const pn: *N = @fieldParentPtr("node", dl_pn);
                    try updateFrequency(allocator, ipq, Pair.init(pn.data, left), -1);
                }

                // 2. Perform the merge. This replaces `node.data` with `replacement`
                // and removes `next_node`.
                const node_to_remove = next_dl_node;
                const next_next_node = node_to_remove.next;

                // Remove and free the next node
                list.remove(node_to_remove);
                allocator.destroy(node_to_remove);

                // Replace the data in the current node
                node.data = replacement;

                // 3. & 4. Update frequencies for right-side and newly created pairs.
                if (next_next_node) |dl_nnn| {
                    const nnn: *N = @fieldParentPtr("node", dl_nnn);
                    // Decrement the old pair on the right: (right, next_next_node.data)
                    try updateFrequency(allocator, ipq, Pair.init(right, nnn.data), -1);
                    // Increment the new pair on the right: (replacement, next_next_node.data)
                    try updateFrequency(allocator, ipq, Pair.init(replacement, nnn.data), 1);
                }
                if (prev_node) |dl_pn| {
                    const pn: *N = @fieldParentPtr("node", dl_pn);
                    // Increment the new pair on the left: (prev_node.data, replacement)
                    try updateFrequency(allocator, ipq, Pair.init(pn.data, replacement), 1);
                }

                // 5. The current `node` (now containing `replacement`) is the "previous"
                // node for the next iteration.
                prev_node = dl_node;
                current_node = next_next_node; // Move iterator to the node after the removed one
            } else {
                // No match, just advance normally.
                prev_node = dl_node;
                current_node = dl_node.next;
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
    defer _ = gpa.deinit();
    const backing_allocator = gpa.allocator();

    // var arena_state = std.heap.ArenaAllocator.init(backing_allocator);
    // defer arena_state.deinit();

    // const allocator = arena_state.allocator();
    const allocator = backing_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file_path>\n", .{args[0]});
        return;
    }

    const file_path = args[1];
    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();

    const max_file_size = 1 * 1024 * 1024 * 1024; // 1 GB
    const file_contents = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(file_contents);

    const data_as_u32 = try allocator.alloc(u32, file_contents.len);
    defer allocator.free(data_as_u32);

    std.debug.print("Preparing pcre2 ...\n", .{});

    var matcher = try pcre2_matcher.init(allocator, GPT4_SPLIT_PATTERN);
    defer matcher.deinit();

    const match_data = c.pcre2_match_data_create_from_pattern_8(matcher.compiled_pattern, null);
    if (match_data == null) {
        return error.OutOfMemory;
    }
    defer c.pcre2_match_data_free_8(match_data);

    const general_context_pcre2 = c.pcre2_general_context_create_8(null, null, null);
    const match_context_pcre2 = c.pcre2_match_context_create_8(general_context_pcre2);

    std.debug.print("Splitting string...\n", .{});

    var chunks = try ArrayList([]u8).initCapacity(allocator, 128);
    defer chunks.deinit(allocator);

    // Gather a hashmap of word frequency as we split it up
    var word_freq = StringHashMap(usize).init(allocator);
    defer word_freq.deinit();

    var rc: c_int = undefined;
    var start_offset: usize = 0;

    while (true) {
        rc = c.pcre2_match_8(matcher.compiled_pattern, file_contents.ptr, file_contents.len, start_offset, c.PCRE2_NO_UTF_CHECK, match_data, match_context_pcre2);

        if (rc == c.PCRE2_ERROR_NOMATCH) {
            break;
        }
        if (rc < 0) {
            std.debug.print("PCRE2 Error: {d}\n", .{rc});
            break;
        }

        const ovector = c.pcre2_get_ovector_pointer_8(match_data);

        // ovector[0] is start of match, ovector[1] is end of match
        const match_start = ovector[0];
        const match_end = ovector[1];

        const match = file_contents[match_start..match_end];

        // std.debug.print("{s}\n", .{match});

        const result = try word_freq.getOrPut(match);
        if (result.found_existing) {
            result.value_ptr.* = result.value_ptr.* + 1;
        } else {
            result.value_ptr.* = 1;
        }

        start_offset = match_end;

        if (match_end == match_start) {
            start_offset += 1;
            if (start_offset > file_contents.len) break;
        }
    }

    std.debug.print("Number of distinct words: {d}\n", .{word_freq.count()});

    // // TODO this shouldn't be needed right?
    // for (file_contents, 0..) |b, i| {
    //     data_as_u32[i] = b;
    // }

    // var list : std.DoublyLinkedList = .{};
    // // Defer freeing all nodes that were allocated for the list.
    // defer {
    //     while (list.popFirst()) |node| {
    //         allocator.destroy(node);
    //     }
    // }

    // // Manually create nodes and append them to the list.
    // // TODO this should be an array of nodes
    // for (data_as_u32) |token| {
    //     const node = try allocator.create(N);
    //     node.data = token;
    //     list.append(&node.node);
    // }

    // const output_buffer_size = 1024 * 1024; // 1 Kb
    // const output_buffer = try allocator.alloc(u8, output_buffer_size);
    // defer allocator.free(output_buffer);

    // const stdout = std.fs.File.stdout();
    // var writer = stdout.writer(output_buffer);
    // try writer.interface.print("File size: {d} bytes, DoublyLinkedList size: {d}\n", .{ file_contents.len, list.len() });

    // // Steps
    // // 1. Set up the main loop with the target token size
    // // 2. Loop over the data counting frequencies and keep the most frequent pair
    // // 3. Replace the most frequent pair with a new token

    // const target_token_size = 512;
    // var current_token: TokenType = 256;

    // const start_time = std.time.nanoTimestamp();

    // // Key - pair
    // // Value - frequency
    // const IntIntMaxIPQ = IndexedPriorityQueue.IndexedPriorityQueue(Pair, usize, void, maxHeapComparator);

    // // Create an instance of the IPQ.
    // var ipq = IntIntMaxIPQ.init(allocator, {});
    // defer ipq.deinit(allocator);

    // while (current_token < target_token_size) {
    //     const step_start_time = std.time.nanoTimestamp();
    //     // When there's only one pair or less we cannot continue
    //     // TODO len is linear, need to track it
    //     if (list.len() < 2) {
    //         break;
    //     }

    //     // When the ipq is empty it means we need to do a full iteration and count the frequencies
    //     if (ipq.isEmpty()) {
    //         const initial_count_start_time = std.time.nanoTimestamp();
    //         try writer.interface.print("Initial count\n", .{});
    //         var current_node = list.first;
    //         while (current_node) |node| {
    //             const node_parent: *N = @fieldParentPtr("node", node);
    //             // Get the current and next tokens by looking at the next node
    //             if (node.next) |next_node| {
    //                 const next_node_parent: *N = @fieldParentPtr("node", next_node);
    //                 const pair = Pair.init(node_parent.data, next_node_parent.data);
    //                 const freq_entry = ipq.get(pair);

    //                 if (freq_entry) |entry| {
    //                     _ = try ipq.changeValue(pair, entry.value + 1);
    //                 } else {
    //                     _ = try ipq.push(allocator, pair, 1);
    //                 }
    //             }
    //             current_node = node.next;
    //         }
    //         const initial_count_end_time = std.time.nanoTimestamp();
    //         const initial_count_elapsed_nanoseconds = initial_count_end_time - initial_count_start_time;
    //         try writer.interface.print("Initial count time elapsed: {} ms\n", .{@divTrunc(initial_count_elapsed_nanoseconds, std.time.ns_per_ms)});
    //     }

    //     // Get the most frequent pair
    //     const most_frequent = try ipq.pop();
    //     const most_frequent_pair = most_frequent.key;

    //     // do the replacement and modify the ipq as we go
    //     mergePairs(TokenType, &list, allocator, &ipq, most_frequent_pair.first, most_frequent_pair.second, current_token) catch {
    //         try writer.interface.print("Error during merging pairs\n", .{});
    //         break;
    //     };

    //     // debug print the most frequent pair
    //     try writer.interface.print("Most frequent pair so far: ({d}, {d}) with frequency {d}\n", .{ most_frequent_pair.first, most_frequent_pair.second, most_frequent.value });
    //     current_token += 1;

    //     const step_end_time = std.time.nanoTimestamp();
    //     const step_elapsed_nanoseconds = step_end_time - step_start_time;
    //     try writer.interface.print("Step time elapsed: {} ms\n", .{@divTrunc(step_elapsed_nanoseconds, std.time.ns_per_ms)});
    //     try writer.interface.flush();
    // }

    // const end_time = std.time.nanoTimestamp();
    // const elapsed_nanoseconds = end_time - start_time;
    // try writer.interface.print("Total time elapsed: {} ms\n", .{@divTrunc(elapsed_nanoseconds, std.time.ns_per_ms)});
    // try writer.interface.print("File size: {d} bytes, DoublyLinkedList size: {d}\n", .{ file_contents.len, list.len() });
    // try writer.interface.flush();
}
