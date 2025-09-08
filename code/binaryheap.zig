const std = @import("std");
const ArrayList = std.ArrayList;

pub fn BinaryHeap(comptime Child: type) type {
    return struct {
        const Self = @This();

        pub const MovedElement = struct {
            value: Child,
            new_index: usize,
        };

        pub const ExtractResult = struct {
            min_value: Child,
            moved_element: ?MovedElement,
        };

        items: ArrayList(Child),
        lessThan: *const fn (a: Child, b: Child) bool,

        // Initialize the binary heap
        pub fn initCapacity(allocator: std.mem.Allocator, initialCapacity: usize, lessThanFn: *const fn (Child, Child) bool) !Self {
            const items = try ArrayList(Child).initCapacity(allocator, initialCapacity);
            return Self{
                .items = items,
                .lessThan = lessThanFn,
            };
        }

        // Deinitialize the binary heap
        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        // Get the index of the parent node
        fn parentIndex(index: usize) usize {
            return (index - 1) / 2;
        }

        // Get the index of the left child node
        fn leftChildIndex(index: usize) usize {
            return 2 * index + 1;
        }

        // Get the index of the right child node
        fn rightChildIndex(index: usize) usize {
            return 2 * index + 2;
        }

        // Swap two elements in the heap
        fn swap(self: *Self, i: usize, j: usize) void {
            const temp = self.items.items[i];
            self.items.items[i] = self.items.items[j];
            self.items.items[j] = temp;
        }

        // Heapify up (used after insertion or key increase)
        fn heapifyUp(self: *Self, index: usize) usize {
            var current = index;
            while (current > 0 and self.lessThan(self.items.items[current], self.items.items[parentIndex(current)])) {
                self.swap(current, parentIndex(current));
                current = parentIndex(current);
            }
            return current;
        }

        // Heapify down (used after extraction or key decrease)
        fn heapifyDown(self: *Self, index: usize) usize {
            var current = index;
            while (true) {
                const left = leftChildIndex(current);
                const right = rightChildIndex(current);
                var smallest = current;

                if (left < self.items.items.len and self.lessThan(self.items.items[left], self.items.items[smallest])) {
                    smallest = left;
                }

                if (right < self.items.items.len and self.lessThan(self.items.items[right], self.items.items[smallest])) {
                    smallest = right;
                }

                if (smallest == current) break;

                self.swap(current, smallest);
                current = smallest;
            }
            return current;
        }

        // Insert a new element into the heap and return its index
        pub fn insert(self: *Self, value: Child) !usize {
            try self.items.append(value);
            return self.heapifyUp(self.items.items.len - 1);
        }

        // Modify an element at a given index and return its new index
        pub fn modify(self: *Self, index: usize, value: Child) usize {
            const old_value = self.items.items[index];
            self.items.items[index] = value;

            if (self.lessThan(value, old_value)) {
                return self.heapifyUp(index);
            } else {
                return self.heapifyDown(index);
            }
        }

        // Extract the minimum element from the heap
        pub fn extractMin(self: *Self) ?ExtractResult {
            if (self.items.items.len == 0) return null;

            const min = self.items.items[0];

            if (self.items.items.len == 1) {
                _ = self.items.pop();
                return ExtractResult{
                    .min_value = min,
                    .moved_element = null,
                };
            }

            const last_val = self.items.pop().?;
            self.items.items[0] = last_val;
            const new_index = self.heapifyDown(0);

            return ExtractResult{
                .min_value = min,
                .moved_element = MovedElement{
                    .value = last_val,
                    .new_index = new_index,
                },
            };
        }

        // Peek at the minimum element without removing it
        pub fn peekMin(self: *Self) ?Child {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        // Clears all the values, effectively emptying the queue.
        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        pub fn count(self: *Self) usize {
            return self.items.items.len;
        }
    };
}

const testing = std.testing;

fn i32LessThan(a: i32, b: i32) bool {
    return a < b;
}

test "Basic" {
    var heap = try BinaryHeap(i32).initCapacity(testing.allocator, 10, i32LessThan);
    defer heap.deinit();

    _ = try heap.insert(10);
    _ = try heap.insert(5);
    _ = try heap.insert(20);
    _ = try heap.insert(12);
    _ = try heap.insert(7);
    _ = try heap.insert(8);
    _ = try heap.insert(17);
    _ = try heap.insert(5);
    _ = try heap.insert(22);

    try testing.expect(heap.extractMin().?.min_value == 5);
    try testing.expect(heap.extractMin().?.min_value == 5);
    try testing.expect(heap.extractMin().?.min_value == 7);
    try testing.expect(heap.extractMin().?.min_value == 8);
    try testing.expect(heap.extractMin().?.min_value == 10);
    try testing.expect(heap.extractMin().?.min_value == 12);
    try testing.expect(heap.extractMin().?.min_value == 17);
    try testing.expect(heap.extractMin().?.min_value == 20);
    try testing.expect(heap.extractMin().?.min_value == 22);
    try testing.expect(heap.extractMin() == null);

    _ = try heap.insert(10);
    _ = try heap.insert(5);
    _ = try heap.insert(20);

    try testing.expect(heap.extractMin().?.min_value == 5);
    try testing.expect(heap.extractMin().?.min_value == 10);
    try testing.expect(heap.extractMin().?.min_value == 20);
    try testing.expect(heap.extractMin() == null);
}

test "Expand capacity" {
    var heap = try BinaryHeap(i32).initCapacity(testing.allocator, 5, i32LessThan);
    defer heap.deinit();

    _ = try heap.insert(10);
    _ = try heap.insert(5);
    _ = try heap.insert(20);
    _ = try heap.insert(12);
    _ = try heap.insert(7);
    _ = try heap.insert(8);
    _ = try heap.insert(17);
    _ = try heap.insert(5);
    _ = try heap.insert(22);

    try testing.expect(heap.extractMin().?.min_value == 5);
    try testing.expect(heap.extractMin().?.min_value == 5);
    try testing.expect(heap.extractMin().?.min_value == 7);
    try testing.expect(heap.extractMin().?.min_value == 8);
    try testing.expect(heap.extractMin().?.min_value == 10);
    try testing.expect(heap.extractMin().?.min_value == 12);
    try testing.expect(heap.extractMin().?.min_value == 17);
    try testing.expect(heap.extractMin().?.min_value == 20);
    try testing.expect(heap.extractMin().?.min_value == 22);
    try testing.expect(heap.extractMin() == null);
}

const Coord = struct {
    row: i32,
    col: i32,
};

const fScoreEntry = struct {
    coord: Coord,
    score: i32,
};

fn fScoreLessThan(a: fScoreEntry, b: fScoreEntry) bool {
    return a.score < b.score;
}

test "With custom struct" {
    var heap = try BinaryHeap(fScoreEntry).initCapacity(testing.allocator, 5, fScoreLessThan);
    defer heap.deinit();

    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 10 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 5 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 20 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 25 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 12 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 8 });

    try testing.expect(heap.extractMin().?.min_value.score == 5);
    try testing.expect(heap.extractMin().?.min_value.score == 8);
}
