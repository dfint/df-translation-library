/// A simple parser for GNU Gettext .mo files.
/// Does not support plural forms (yet?)
/// Format description: https://www.gnu.org/software/gettext/manual/html_node/MO-Files.html
const std = @import("std");

const MoParserError = error{
    InvalidFormat,
};

const CONTEXT_SEPARATOR: []const u8 = "\x04";

const MoFileEntry = struct {
    original_string: []const u8,
    context: ?[]const u8 = undefined,
    translation_string: []const u8,

    _full_original_string: []const u8,

    const Self = @This();

    pub fn init(original_string: []const u8, translation_string: []const u8) Self {
        var self: Self = .{
            .original_string = original_string,
            .translation_string = translation_string,
            ._full_original_string = original_string,
        };
        self.extractContext();

        return self;
    }

    fn extractContext(self: *Self) void {
        if (std.mem.indexOf(u8, self.original_string, CONTEXT_SEPARATOR)) |index| {
            self.context = self.original_string[0..index];
            self.original_string = self.original_string[index + 1 ..];
        } else {
            self.context = null;
        }
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self._full_original_string);
        allocator.free(self.translation_string);
    }
};

test "MoFileEntry no allocation" {
    const original_string = "context\x04original string";
    const translation_string = "translation string";

    const mo_entry = MoFileEntry.init(original_string, translation_string);

    try std.testing.expectEqualStrings("original string", mo_entry.original_string);
    try std.testing.expectEqualStrings("context", mo_entry.context orelse "");
    try std.testing.expectEqualStrings("translation string", mo_entry.translation_string);
    try std.testing.expectEqualStrings("context\x04original string", mo_entry._full_original_string);
}

test "MoFileEntry with allocation" {
    var allocator = std.testing.allocator;
    const original_string = allocator.dupe(u8, "context\x04original string") catch unreachable;
    const translation_string = allocator.dupe(u8, "translation string") catch unreachable;

    const mo_entry = MoFileEntry.init(original_string, translation_string);
    defer mo_entry.deinit(allocator);

    try std.testing.expectEqualStrings("original string", mo_entry.original_string);
    try std.testing.expectEqualStrings("context", mo_entry.context orelse "");
    try std.testing.expectEqualStrings("translation string", mo_entry.translation_string);
    try std.testing.expectEqualStrings("context\x04original string", mo_entry._full_original_string);
}

const MoParser = struct {
    const MO_MAGIC_LE = "\xde\x12\x04\x95";
    const MO_MAGIC_BE = "\x95\x04\x12\xde";

    file: std.fs.File,
    mo_header_info: MoHeaderInfo = undefined,

    const Self = @This();

    pub fn init(file: std.fs.File) !Self {
        return .{
            .file = file,
            .mo_header_info = try Self.readHeader(file),
        };
    }

    fn readHeader(file: std.fs.File) !MoHeaderInfo {
        try file.seekTo(0);
        const magic = try file.reader().readBytesNoEof(MO_MAGIC_LE.len);

        var byteorder: std.builtin.Endian = undefined;
        if (std.mem.eql(u8, &magic, MO_MAGIC_LE)) {
            byteorder = .little;
        } else if (std.mem.eql(u8, &magic, MO_MAGIC_BE)) {
            byteorder = .big;
        } else {
            return MoParserError.InvalidFormat;
        }

        try file.seekTo(8);
        return .{
            .byteorder = byteorder,
            .number_of_strings = try file.reader().readInt(u32, byteorder),
            .original_string_table_offset = try file.reader().readInt(u32, byteorder),
            .translation_string_table_offset = try file.reader().readInt(u32, byteorder),
        };
    }

    const MoHeaderInfo = struct {
        byteorder: std.builtin.Endian,
        number_of_strings: u32,
        original_string_table_offset: u32,
        translation_string_table_offset: u32,
    };

    pub fn iterateEntries(self: Self, allocator: std.mem.Allocator) !Iterator {
        return Iterator{
            .file = self.file,
            .mo_header_info = self.mo_header_info,
            .allocator = allocator,
        };
    }

    const Iterator = struct {
        allocator: std.mem.Allocator,
        i: u32 = 0,
        file: std.fs.File,
        mo_header_info: MoHeaderInfo,
        value: ?MoFileEntry = null,

        /// .deinit() of the iterator must be called only if the iterator was not exhausted
        pub fn deinit(self: *Iterator) void {
            if (self.value) |value| {
                value.deinit(self.allocator);
                self.value = null;
            }
        }

        pub fn next(self: *Iterator) !?MoFileEntry {
            if (self.value) |value| {
                value.deinit(self.allocator);
                self.value = null;
            }

            if (self.i >= self.mo_header_info.number_of_strings) {
                return null;
            }
            defer self.i += 1;

            const original_string_table_offset = self.mo_header_info.original_string_table_offset;
            const translation_string_table_offset = self.mo_header_info.translation_string_table_offset;
            self.value = MoFileEntry.init(
                try self.readString(original_string_table_offset, self.i),
                try self.readString(translation_string_table_offset, self.i),
            );
            return self.value;
        }

        const STRING_TABLE_ENTRY_SIZE = 8;

        fn readString(self: *Iterator, table_offset: u32, index: u32) ![]const u8 {
            try self.file.seekTo(table_offset + index * STRING_TABLE_ENTRY_SIZE);
            const string_size = try self.file.reader().readInt(u32, self.mo_header_info.byteorder);
            const string_offset = try self.file.reader().readInt(u32, self.mo_header_info.byteorder);

            try self.file.seekTo(string_offset);
            const string = try self.allocator.alloc(u8, string_size);
            _ = try self.file.reader().read(string);
            return string;
        }
    };
};

test "MoParser" {
    const file = try std.fs.cwd().openFile("test_data/test.mo", .{});
    const parser = try MoParser.init(file);
    const expected_number_of_strings: u32 = 5;
    try std.testing.expectEqual(expected_number_of_strings, parser.mo_header_info.number_of_strings);

    var iterator = try parser.iterateEntries(std.testing.allocator);

    var i: u32 = 0;
    while (try iterator.next()) |entry| {
        try std.testing.expect(entry.context == null or entry.context.?.len > 0 and entry.context.?.len < 100);
        try std.testing.expect(entry.original_string.len < 100);
        try std.testing.expect(entry.translation_string.len > 0 and entry.translation_string.len < 100);
        i += 1;
    }
    try std.testing.expectEqual(expected_number_of_strings, i);
}

pub fn print_mo(mo_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(mo_path, .{});
    defer file.close();

    const parser = try MoParser.init(file);
    const mo_header_info = parser.mo_header_info;
    std.debug.print("number of strings: {d}\n", .{mo_header_info.number_of_strings});
    std.debug.print("original string table offset: {d}\n", .{mo_header_info.original_string_table_offset});
    std.debug.print(
        "translation string table offset: {d}\n\n",
        .{mo_header_info.translation_string_table_offset},
    );

    var debug_allocator = std.heap.DebugAllocator(.{}){};
    const allocator = debug_allocator.allocator();
    var iterator = try parser.iterateEntries(allocator);
    while (try iterator.next()) |entry| {
        // defer entry.deinit(allocator);

        std.debug.print("context: {s}\noriginal: {s}\ntranslation: {s}\n\n", .{
            entry.context orelse "NULL",
            entry.original_string,
            entry.translation_string,
        });
    }
}

const DictionaryKey = struct {
    context: ?[]const u8 = null,
    original_string: []const u8,
};

const Dictionary = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),

    fn init(allocator: std.mem.Allocator) Dictionary {
        return Dictionary{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn load(allocator: std.mem.Allocator, po_path: []const u8) !Dictionary {
        const file = try std.fs.cwd().openFile(po_path, .{});
        const parser = try MoParser.init(file);
        var dictionary = Dictionary.init(allocator);
        var iterator = try parser.iterateEntries(allocator);
        while (try iterator.next()) |entry| {
            if (entry.original_string.len == 0) continue;
            try dictionary.put(entry);
        }
        return dictionary;
    }

    pub fn deinit(self: *Dictionary) void {
        var items = self.entries.iterator();
        while (items.next()) |item| {
            self.allocator.free(item.key_ptr.*);
            self.allocator.free(item.value_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn put(self: *Dictionary, mo_file_entry: MoFileEntry) !void {
        const key = self.allocator.dupe(u8, mo_file_entry._full_original_string) catch unreachable;
        const value = self.allocator.dupe(u8, mo_file_entry.translation_string) catch unreachable;
        try self.entries.put(key, value);
    }

    pub fn get(self: Dictionary, context: ?[]const u8, original_string: []const u8) !?[]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        if (context) |c| {
            try buffer.appendSlice(c);
            try buffer.appendSlice(CONTEXT_SEPARATOR);
        }
        try buffer.appendSlice(original_string);

        return self.entries.get(buffer.items);
    }
};

test "load dictionary" {
    const allocator = std.testing.allocator;
    var dictionary = try Dictionary.load(allocator, "test_data/test.mo");
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
