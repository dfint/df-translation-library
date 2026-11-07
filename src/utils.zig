const std = @import("std");

/// Create an iterator over a slice of values.
pub fn ArrayIterator(comptime T: type) type {
    return struct {
        entries: []const T,
        index: usize = 0,

        /// Return the next value, or null when the slice is exhausted.
        pub fn next(self: *@This()) ?T {
            if (self.index >= self.entries.len) return null;
            const entry = self.entries[self.index];
            self.index += 1;
            return entry;
        }
    };
}

test "utils: ArrayIterator yields values in order and ends with null" {
    const entries = [_]u8{ 3, 5, 8 };
    var iterator = ArrayIterator(u8){ .entries = &entries };

    try std.testing.expectEqual(@as(?u8, 3), iterator.next());
    try std.testing.expectEqual(@as(?u8, 5), iterator.next());
    try std.testing.expectEqual(@as(?u8, 8), iterator.next());
    try std.testing.expectEqual(@as(?u8, null), iterator.next());
}

test "utils: ArrayIterator handles an empty slice" {
    const entries: []const u8 = &.{};
    var iterator = ArrayIterator(u8){ .entries = entries };

    try std.testing.expectEqual(@as(?u8, null), iterator.next());
}

/// Collect items from iterator into ArrayList
pub fn collectIterator(comptime T: type, allocator: std.mem.Allocator, iterator: anytype) !std.ArrayList(T) {
    var array: std.ArrayList(T) = .empty;

    while (iterator.next()) |token| {
        try array.append(allocator, token);
    }

    return array;
}

test "utils: collectIterator collects values in order" {
    const allocator = std.testing.allocator;
    const entries = [_]u8{ 2, 4, 6 };
    var iterator = ArrayIterator(u8){ .entries = &entries };
    var collected = try collectIterator(u8, allocator, &iterator);
    defer collected.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &entries, collected.items);
}

test "utils: collectIterator handles an empty iterator" {
    const allocator = std.testing.allocator;
    const entries: []const u8 = &.{};
    var iterator = ArrayIterator(u8){ .entries = entries };
    var collected = try collectIterator(u8, allocator, &iterator);
    defer collected.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), collected.items.len);
}
