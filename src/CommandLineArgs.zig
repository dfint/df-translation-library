const std = @import("std");
const collections = @import("zig_collections");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayList;

_arena: *ArenaAllocator,
_lookup: std.StringHashMapUnmanaged([]const u8),

const Self = @This();

pub fn parseFromIterator(arena: *ArenaAllocator, it: anytype) !Self {
    var allocator = arena.allocator();
    const EmptyArrayListFactory = struct {
        fn produce(_: @This()) ArrayListUnmanaged([]const u8) {
            return .empty;
        }
    };

    var lookup = collections.DefaultHashMap(
        []const u8,
        ArrayListUnmanaged([]const u8),
        EmptyArrayListFactory{},
        EmptyArrayListFactory.produce,
    ).init(allocator);

    var key: ?[]const u8 = null;
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            key = try allocator.dupe(u8, arg[2..]);
        } else if (key) |key_value| {
            try lookup.get(key_value).append(try allocator.dupe(u8, arg));
        }
    }

    return .{
        ._arena = arena,
        ._lookup = lookup,
    };
}

pub fn deinit(self: Self) !void {
    defer self._lookup.deinitUnmanaged(self._arena);
}
