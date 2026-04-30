//! Interner for strings: creates one copy for each unique string from passed strings.
//! Frees all the interned strings on deinit.
const std = @import("std");

map: std.StringHashMap(void),
allocator: std.mem.Allocator,

const Self = @This();

/// Initialize interner.
pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .map = std.StringHashMap(void).init(allocator),
        .allocator = allocator,
    };
}

/// Deininialize interner.
pub fn deinit(self: *Self) void {
    var it = self.map.keyIterator();
    while (it.next()) |key| {
        self.allocator.free(key.*);
    }
    self.map.deinit();
}

/// Create a copy of a string if it has not been stored in the internal map yet,
/// otherwise return exisitng string copy from the map.
pub fn intern(self: *Self, string: []const u8) ![]const u8 {
    if (self.map.getKey(string)) |existing| {
        return existing;
    }

    const copy = try self.allocator.dupe(u8, string);
    try self.map.put(copy, {});
    return copy;
}

test "Interner" {
    const allocator = std.testing.allocator;
    var interner = Self.init(allocator);
    defer interner.deinit();

    const test_string: []const u8 = "test1";
    const interned_string1 = try interner.intern(test_string);
    try std.testing.expectEqualStrings(test_string, interned_string1);
    try std.testing.expect(test_string.ptr != interned_string1.ptr);
    const interned_string2 = try interner.intern(test_string);
    try std.testing.expect(interned_string1.ptr == interned_string2.ptr);
}
