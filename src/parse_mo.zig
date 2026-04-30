//! A simple parser for GNU Gettext .mo files.
//! Does not support plural forms (yet?)
//! Format description: https://www.gnu.org/software/gettext/manual/html_node/MO-Files.html
const std = @import("std");

const dictionary = @import("dictionary.zig");
const DictionaryKey = dictionary.DictionaryKey;

const MoParserError = error{
    InvalidFormat,
};

const CONTEXT_SEPARATOR: []const u8 = "\x04";

/// Structure, which describes an entry of a MO file.
const MoFileEntry = struct {
    key: DictionaryKey,
    translation_string: []const u8,
    _full_original_string: []const u8,

    const Self = @This();

    /// Initialize the structure.
    pub fn init(original_string: []const u8, translation_string: []const u8) Self {
        return .{
            .key = MoFileEntry.extractKey(original_string),
            .translation_string = translation_string,
            ._full_original_string = original_string,
        };
    }

    /// Split original string into string and context, return dictionary entry key.
    fn extractKey(full_original_string: []const u8) DictionaryKey {
        if (std.mem.indexOf(u8, full_original_string, CONTEXT_SEPARATOR)) |index| {
            return .{
                .original_string = full_original_string[index + 1 ..],
                .context = full_original_string[0..index],
            };
        }

        return .{
            .original_string = full_original_string,
            .context = null,
        };
    }

    /// Deinitialize the structure.
    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self._full_original_string);
        allocator.free(self.translation_string);
    }
};

test "MoFileEntry no allocation" {
    const original_string = "context\x04original string";
    const translation_string = "translation string";

    const mo_entry = MoFileEntry.init(original_string, translation_string);

    try std.testing.expectEqualStrings("original string", mo_entry.key.original_string);
    try std.testing.expectEqualStrings("context", mo_entry.key.context orelse "");
    try std.testing.expectEqualStrings("translation string", mo_entry.translation_string);
    try std.testing.expectEqualStrings("context\x04original string", mo_entry._full_original_string);
}

test "MoFileEntry with allocation" {
    var allocator = std.testing.allocator;
    const original_string = allocator.dupe(u8, "context\x04original string") catch unreachable;
    const translation_string = allocator.dupe(u8, "translation string") catch unreachable;

    const mo_entry = MoFileEntry.init(original_string, translation_string);
    defer mo_entry.deinit(allocator);

    try std.testing.expectEqualStrings("original string", mo_entry.key.original_string);
    try std.testing.expectEqualStrings("context", mo_entry.key.context orelse "");
    try std.testing.expectEqualStrings("translation string", mo_entry.translation_string);
    try std.testing.expectEqualStrings("context\x04original string", mo_entry._full_original_string);
}

/// Parser of MO files.
pub const MoParser = struct {
    const MO_MAGIC_LE = "\xde\x12\x04\x95";
    const MO_MAGIC_BE = "\x95\x04\x12\xde";

    io: std.Io,
    file: std.Io.File,
    mo_header_info: MoHeaderInfo,

    const Self = @This();

    /// Initialize the parser.
    pub fn init(io: std.Io, file: std.Io.File) !Self {
        return .{
            .io = io,
            .file = file,
            .mo_header_info = try Self.readHeader(io, file),
        };
    }

    /// Determine byte order by the magic number in the file header.
    fn getByteorder(magic: []u8) MoParserError!std.builtin.Endian {
        if (std.mem.eql(u8, magic, MO_MAGIC_LE)) {
            return .little;
        } else if (std.mem.eql(u8, magic, MO_MAGIC_BE)) {
            return .big;
        } else return MoParserError.InvalidFormat;
    }

    /// Read the file header
    fn readHeader(io: std.Io, file: std.Io.File) !MoHeaderInfo {
        var buffer: [@max(@sizeOf(u32), MO_MAGIC_LE.len)]u8 = undefined;
        var reader = file.reader(io, &buffer);
        try reader.seekTo(0);

        const magic = try reader.interface.peek(MO_MAGIC_LE.len);
        const byteorder: std.builtin.Endian = try MoParser.getByteorder(magic);

        try reader.seekTo(8);
        return .{
            .byteorder = byteorder,
            .number_of_strings = try reader.interface.takeInt(u32, byteorder),
            .original_string_table_offset = try reader.interface.takeInt(u32, byteorder),
            .translation_string_table_offset = try reader.interface.takeInt(u32, byteorder),
        };
    }

    /// Structure, which describes MO file header.
    const MoHeaderInfo = struct {
        byteorder: std.builtin.Endian,
        number_of_strings: u32,
        original_string_table_offset: u32,
        translation_string_table_offset: u32,
    };

    /// Get iterator over MO file entries.
    pub fn iterateEntries(self: Self, allocator: std.mem.Allocator) !Iterator {
        return Iterator{
            .io = self.io,
            .file = self.file,
            .mo_header_info = self.mo_header_info,
            .allocator = allocator,
        };
    }

    /// Iterator over MO file entries.
    const Iterator = struct {
        io: std.Io,
        allocator: std.mem.Allocator,
        i: u32 = 0,
        file: std.Io.File,
        mo_header_info: MoHeaderInfo,
        value: ?MoFileEntry = null,

        /// Deinitialize the iterator.
        /// .deinit() of the iterator must be called only if the iterator was not exhausted
        pub fn deinit(self: *Iterator) void {
            if (self.value) |value| {
                value.deinit(self.allocator);
                self.value = null;
            }
        }

        /// Get the next file entry. Returns pair of a dictinary key and translation string (dictionary value)
        pub fn next(self: *Iterator) !?struct { DictionaryKey, []const u8 } {
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
            const value = MoFileEntry.init(
                try self.readString(original_string_table_offset, self.i),
                try self.readString(translation_string_table_offset, self.i),
            );
            self.value = value;
            return .{ value.key, value.translation_string };
        }

        const STRING_TABLE_ENTRY_SIZE = 8;

        /// Read string from the file by table offset and string index.
        fn readString(self: *Iterator, table_offset: u32, index: u32) ![]const u8 {
            var buffer: [1024]u8 = undefined;
            var reader = self.file.reader(self.io, &buffer);
            try reader.seekTo(table_offset + index * STRING_TABLE_ENTRY_SIZE);
            const string_size = try reader.interface.takeInt(u32, self.mo_header_info.byteorder);
            const string_offset = try reader.interface.takeInt(u32, self.mo_header_info.byteorder);

            try reader.seekTo(string_offset);
            return try reader.interface.readAlloc(self.allocator, string_size);
        }
    };
};

test "MoParser" {
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, "test_data/test.mo", .{});
    const parser = try MoParser.init(io, file);
    const expected_number_of_strings: u32 = 5;
    try std.testing.expectEqual(expected_number_of_strings, parser.mo_header_info.number_of_strings);

    var iterator = try parser.iterateEntries(std.testing.allocator);

    var i: u32 = 0;
    while (try iterator.next()) |entry| {
        const key = entry[0];
        const translation_string = entry[1];
        try std.testing.expect(key.context == null or key.context.?.len > 0 and key.context.?.len < 100);
        try std.testing.expect(key.original_string.len < 100);
        try std.testing.expect(translation_string.len > 0 and translation_string.len < 100);
        i += 1;
    }
    try std.testing.expectEqual(expected_number_of_strings, i);
}
