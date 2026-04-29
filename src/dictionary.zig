const std = @import("std");

const parse_mo = @import("parse_mo.zig");

pub const DictionaryEntry = struct {
    key: Key,
    translation_string: []const u8,

    pub const Key = struct {
        original_string: []const u8,
        context: ?[]const u8 = null,

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            return .{
                .original_string = try allocator.dupe(u8, self.original_string),
                .context = if (self.context) |cont| try allocator.dupe(u8, cont) else null,
            };
        }

        pub fn free(self: @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.original_string);
            if (self.context) |context| {
                allocator.free(context);
            }
        }
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
        var items = self.entries.iterator();
        while (items.next()) |item| {
            item.key_ptr.*.free(self.allocator);
            self.allocator.free(item.value_ptr.*);
        }
        self.entries.deinit();
    }

    /// Put an entry into the dictionary.
    pub fn put(self: *Dictionary, mo_file_entry: DictionaryEntry) !void {
        const value = try self.allocator.dupe(u8, mo_file_entry.translation_string);
        try self.entries.put(try mo_file_entry.key.clone(self.allocator), value);
    }

    /// Get translation by original string and context.
    pub fn get(self: Dictionary, context: ?[]const u8, original_string: []const u8) !?[]const u8 {
        return self.entries.get(.{
            .original_string = original_string,
            .context = context,
        });
    }
};

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
