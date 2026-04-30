const std = @import("std");

/// Collect items from iterator into ArrayList
pub fn collectIterator(comptime T: type, allocator: std.mem.Allocator, iterator: anytype) !std.ArrayList(T) {
    var array: std.ArrayList(T) = .empty;

    while (iterator.next()) |token| {
        try array.append(allocator, token);
    }

    return array;
}
