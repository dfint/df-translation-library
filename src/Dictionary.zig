//! Dictionary container structure.

const std = @import("std");

const StringInterner = @import("StringInterner.zig");

/// Key of the Dictionary
pub const DictionaryKey = struct {
    original_string: []const u8,
    context: ?[]const u8 = null,
};

/// Hashing context is necessary to make it possible to use DictionaryKey as a key of HashMap.
const HashingContext = struct {
    pub fn hash(_: HashingContext, key: DictionaryKey) u64 {
        var hasher = std.hash.Wyhash.init(0);

        // hash original_string string
        hasher.update(key.original_string);

        // distinguish null vs non-null
        if (key.context) |s| {
            hasher.update(&[_]u8{1}); // tag: present
            hasher.update(s);
        } else {
            hasher.update(&[_]u8{0}); // tag: null
        }

        return hasher.final();
    }

    pub fn eql(_: HashingContext, a: DictionaryKey, b: DictionaryKey) bool {
        if (!std.mem.eql(u8, a.original_string, b.original_string)) return false;

        if (a.context == null and b.context == null) return true;
        if (a.context == null or b.context == null) return false;

        return std.mem.eql(u8, a.context.?, b.context.?);
    }
};

allocator: std.mem.Allocator,
entries: std.HashMap(DictionaryKey, []const u8, HashingContext, 80),
interner: StringInterner,

const Self = @This();

/// Initialize dictionary.
fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .entries = std.HashMap(
            DictionaryKey,
            []const u8,
            HashingContext,
            80,
        ).init(allocator),
        .interner = .init(allocator),
    };
}

/// Get next value from iterator with try (if `.next()` returned `error_union`) or without it.
fn nextValue(iterator: anytype) !?struct { DictionaryKey, []const u8 } {
    const result = iterator.next();
    return switch (@typeInfo(@TypeOf(result))) {
        .error_union => blk: {
            const val = try result;
            break :blk val;
        },
        else => result,
    };
}

/// Populate dictionary from iterator
pub fn loadFromIterator(allocator: std.mem.Allocator, iterator: anytype) !Self {
    var dictionary = Self.init(allocator);
    while (try nextValue(iterator)) |entry| {
        const key: DictionaryKey = entry[0];
        const value: []const u8 = entry[1];
        if (key.original_string.len == 0) continue;
        try dictionary.put(key, value);
    }
    return dictionary;
}

/// Deinitialize dictionary.
pub fn deinit(self: *Self) void {
    self.interner.deinit();
    self.entries.deinit();
}

/// Put an entry into the dictionary.
pub fn put(self: *Self, key: DictionaryKey, value: []const u8) !void {
    const new_value = try self.interner.intern(value);
    const new_key = DictionaryKey{
        .original_string = try self.interner.intern(key.original_string),
        .context = if (key.context) |ctx| try self.interner.intern(ctx) else null,
    };
    try self.entries.put(new_key, new_value);
}

/// Get translation by original string and context.
pub fn get(self: Self, key: DictionaryKey) !?[]const u8 {
    return self.entries.get(key);
}

test "simple dictionary put and get" {
    const allocator = std.testing.allocator;
    var dictionary = Self.init(allocator);
    defer dictionary.deinit();
    const key = DictionaryKey{
        .original_string = "original string",
        .context = "context",
    };
    const value = "translation";
    try dictionary.put(key, value);

    try std.testing.expectEqualStrings(
        "translation",
        (try dictionary.get(key)).?,
    );
}

test "simple dictionary put and get with null context" {
    const allocator = std.testing.allocator;
    var dictionary = Self.init(allocator);
    defer dictionary.deinit();
    const key = DictionaryKey{
        .original_string = "original string",
        .context = null,
    };
    const value = "translation";
    try dictionary.put(key, value);

    try std.testing.expectEqualStrings(
        "translation",
        (try dictionary.get(key)).?,
    );
}

test "simple dictionary get with no value" {
    const allocator = std.testing.allocator;
    var dictionary = Self.init(allocator);
    defer dictionary.deinit();
    const key = DictionaryKey{
        .original_string = "original string",
        .context = null,
    };

    try std.testing.expectEqualDeep(
        null,
        (try dictionary.get(key)),
    );
}

test "try put the same key twice" {
    const allocator = std.testing.allocator;
    var dictionary = Self.init(allocator);
    defer dictionary.deinit();

    const key = DictionaryKey{
        .original_string = "original string",
        .context = "context",
    };
    const value = "translation";
    try dictionary.put(key, value);
    try dictionary.put(key, value); // Can cause a memory leak
}

test "init dictionary from iterator" {
    const allocator = std.testing.allocator;

    const DictEntry = struct { DictionaryKey, []const u8 };
    const ArrayIterator = struct {
        data: []const DictEntry,
        index: usize = 0,

        pub fn next(self: *@This()) ?DictEntry {
            if (self.index >= self.data.len) return null;
            const value = self.data[self.index];
            self.index += 1;
            return value;
        }
    };

    const data = [_]DictEntry{
        .{ .{ .context = null, .original_string = "Text 1" }, "Translation 1" },
        .{ .{ .context = "Context", .original_string = "Text 2" }, "Translation 2" },
    };

    var iterator = ArrayIterator{ .data = &data };
    var dictionary = try Self.loadFromIterator(allocator, &iterator);
    defer dictionary.deinit();

    for (data) |entry| {
        const key = entry[0];
        const translation = entry[1];
        try std.testing.expectEqualStrings(
            translation,
            (try dictionary.get(key)).?,
        );
    }
}
