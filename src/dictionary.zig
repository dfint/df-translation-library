const std = @import("std");

const parse_mo = @import("parse_mo.zig");
const StringInterner = @import("StringInterner.zig");

pub const DictionaryKey = struct {
    original_string: []const u8,
    context: ?[]const u8 = null,
};

const HashingContext = struct {
    const Self = @This();

    pub fn hash(_: Self, key: DictionaryKey) u64 {
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

    pub fn eql(_: Self, a: DictionaryKey, b: DictionaryKey) bool {
        if (!std.mem.eql(u8, a.original_string, b.original_string)) return false;

        if (a.context == null and b.context == null) return true;
        if (a.context == null or b.context == null) return false;

        return std.mem.eql(u8, a.context.?, b.context.?);
    }
};

/// Dictionary container structure.
pub const Dictionary = struct {
    allocator: std.mem.Allocator,
    entries: std.HashMap(DictionaryKey, []const u8, HashingContext, 80),
    interner: StringInterner,

    /// Initialize dictionary.
    fn init(allocator: std.mem.Allocator) Dictionary {
        return Dictionary{
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

    /// Populate dictionary from iterator
    pub fn loadFromIterator(allocator: std.mem.Allocator, iterator: anytype) !Dictionary {
        var dictionary = Dictionary.init(allocator);
        while (try iterator.next()) |entry| {
            const key: DictionaryKey = entry[0];
            const value: []const u8 = entry[1];
            if (key.original_string.len == 0) continue;
            try dictionary.put(key, value);
        }
        return dictionary;
    }

    /// Deinitialize dictionary.
    pub fn deinit(self: *Dictionary) void {
        self.interner.deinit();
        self.entries.deinit();
    }

    /// Put an entry into the dictionary.
    pub fn put(self: *Dictionary, key: DictionaryKey, value: []const u8) !void {
        const new_value = try self.interner.intern(value);
        const new_key = DictionaryKey{
            .original_string = try self.interner.intern(key.original_string),
            .context = if (key.context) |ctx| try self.interner.intern(ctx) else null,
        };
        try self.entries.put(new_key, new_value);
    }

    /// Get translation by original string and context.
    pub fn get(self: Dictionary, key: DictionaryKey) !?[]const u8 {
        return self.entries.get(key);
    }
};

test "simple dictionary put and get" {
    const allocator = std.testing.allocator;
    var dictionary = Dictionary.init(allocator);
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
    var dictionary = Dictionary.init(allocator);
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
    var dictionary = Dictionary.init(allocator);
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
    var dictionary = Dictionary.init(allocator);
    defer dictionary.deinit();

    const key = DictionaryKey{
        .original_string = "original string",
        .context = "context",
    };
    const value = "translation";
    try dictionary.put(key, value);
    try dictionary.put(key, value); // Can cause a memory leak
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
        (try dictionary.get(.{
            .context = null,
            .original_string = "Text 1",
        })).?,
    );
    try std.testing.expectEqualStrings(
        "Translation 2",
        (try dictionary.get(.{
            .context = null,
            .original_string = "Text 2",
        })).?,
    );
    try std.testing.expectEqualStrings(
        "Translation 3",
        (try dictionary.get(.{
            .context = null,
            .original_string = "Text 3",
        })).?,
    );
    try std.testing.expectEqualStrings(
        "Translation 4",
        (try dictionary.get(.{
            .context = "Context",
            .original_string = "Text 4",
        })).?,
    );
    try std.testing.expectEqualDeep(
        null,
        (try dictionary.get(.{
            .context = "Context",
            .original_string = "Text 5",
        })),
    );
}
