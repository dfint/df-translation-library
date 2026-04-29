const std = @import("std");

const parse_mo = @import("parse_mo.zig");

/// Interner for strings stored in dictionary keys.
const StringInterner = struct {
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
};

test "Interner" {
    const allocator = std.testing.allocator;
    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    const test_string: []const u8 = "test1";
    const interned_string1 = try interner.intern(test_string);
    try std.testing.expectEqualStrings(test_string, interned_string1);
    try std.testing.expect(test_string.ptr != interned_string1.ptr);
    const interned_string2 = try interner.intern(test_string);
    try std.testing.expect(interned_string1.ptr == interned_string2.ptr);
}

pub const DictionaryEntry = struct {
    key: Key,
    translation_string: []const u8,

    pub const Key = struct {
        original_string: []const u8,
        context: ?[]const u8 = null,
    };
};

const HashingContext = struct {
    const Self = @This();

    pub fn hash(_: Self, key: DictionaryEntry.Key) u64 {
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

    pub fn eql(_: Self, a: DictionaryEntry.Key, b: DictionaryEntry.Key) bool {
        if (!std.mem.eql(u8, a.original_string, b.original_string)) return false;

        if (a.context == null and b.context == null) return true;
        if (a.context == null or b.context == null) return false;

        return std.mem.eql(u8, a.context.?, b.context.?);
    }
};

/// Dictionary container structure.
pub const Dictionary = struct {
    allocator: std.mem.Allocator,
    entries: std.HashMap(DictionaryEntry.Key, []const u8, HashingContext, 80),
    interner: StringInterner,

    /// Initialize dictionary.
    fn init(allocator: std.mem.Allocator) Dictionary {
        return Dictionary{
            .allocator = allocator,
            .entries = std.HashMap(
                DictionaryEntry.Key,
                []const u8,
                HashingContext,
                80,
            ).init(allocator),
            .interner = .init(allocator),
        };
    }

    /// Populate dictionary from iterator
    pub fn loadFromIterator(allocator: std.mem.Allocator, iterator: anytype) !Dictionary {
        var dictionary = Dictionary.init(allocator);
        while (try iterator.next()) |entry| {
            if (entry.key.original_string.len == 0) continue;
            try dictionary.put(entry);
        }
        return dictionary;
    }

    /// Deinitialize dictionary.
    pub fn deinit(self: *Dictionary) void {
        self.interner.deinit();
        self.entries.deinit();
    }

    /// Put an entry into the dictionary.
    pub fn put(self: *Dictionary, dictionary_entry: DictionaryEntry) !void {
        const value = try self.interner.intern(dictionary_entry.translation_string);
        const key = DictionaryEntry.Key{
            .original_string = try self.interner.intern(dictionary_entry.key.original_string),
            .context = if (dictionary_entry.key.context) |ctx| try self.interner.intern(ctx) else null,
        };
        try self.entries.put(key, value);
    }

    /// Get translation by original string and context.
    pub fn get(self: Dictionary, context: ?[]const u8, original_string: []const u8) !?[]const u8 {
        return self.entries.get(.{
            .original_string = original_string,
            .context = context,
        });
    }
};

test "try put the same key twice" {
    const allocator = std.testing.allocator;
    var dictionary = Dictionary.init(allocator);
    defer dictionary.deinit();
    const entry = DictionaryEntry{
        .key = .{ .original_string = "original string", .context = "context" },
        .translation_string = "translation",
    };
    try dictionary.put(entry);
    try dictionary.put(entry); // Can cause a memory leak
}

test "load dictionary from mo" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const po_path = "test_data/test.mo";
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, po_path, .{});
    const parser = try parse_mo.MoParser.init(io, file);
    var iterator = try parser.iterateEntries(allocator);

    var dictionary = try Dictionary.loadFromIterator(allocator, &iterator);
    defer dictionary.deinit();
    try std.testing.expectEqualStrings(
        "Translation 1",
        (try dictionary.get(null, "Text 1")).?,
    );
    try std.testing.expectEqualStrings(
        "Translation 2",
        (try dictionary.get(null, "Text 2")).?,
    );
    try std.testing.expectEqualStrings(
        "Translation 3",
        (try dictionary.get(null, "Text 3")).?,
    );
    try std.testing.expectEqualStrings(
        "Translation 4",
        (try dictionary.get("Context", "Text 4")).?,
    );
    try std.testing.expect((try dictionary.get("Context", "Text 5")) == null);
}
