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

test "StringInterner: copies new strings and reuses interned copies" {
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

test "StringInterner: reuses interned copy for equal strings from different buffers" {
    const allocator = std.testing.allocator;
    var interner = Self.init(allocator);
    defer interner.deinit();

    var first_input: [6]u8 = "shared".*;
    var second_input: [6]u8 = "shared".*;
    first_input[0] = 'S';
    first_input[0] = 's';
    try std.testing.expect(first_input[0..].ptr != second_input[0..].ptr);

    const first_copy = try interner.intern(&first_input);
    const second_copy = try interner.intern(&second_input);

    try std.testing.expectEqualStrings("shared", first_copy);
    try std.testing.expect(first_copy.ptr == second_copy.ptr);
}

test "StringInterner: stores different strings separately" {
    const allocator = std.testing.allocator;
    var interner = Self.init(allocator);
    defer interner.deinit();

    const first = try interner.intern("first");
    const second = try interner.intern("second");

    try std.testing.expectEqualStrings("first", first);
    try std.testing.expectEqualStrings("second", second);
    try std.testing.expect(first.ptr != second.ptr);
}
