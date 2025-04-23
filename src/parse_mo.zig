const std = @import("std");

const MoParserError = error{
    InvalidFormat,
};

const CONTEXT_SEPARATOR = '\x04';

const MoFileEntry = struct {
    original_string: []const u8,
    context: ?[]const u8 = undefined,
    translation_string: []const u8,

    _full_original_string: []const u8,

    pub fn init(original_string: []const u8, translation_string: []const u8) MoFileEntry {
        const self = .{
            .original_string = original_string,
            .translation_string = translation_string,
            ._full_original_string = original_string,
        };
        self.extractContext();

        return self;
    }

    fn extractContext(self: *MoFileEntry) void {
        if (std.mem.indexOf(u8, self.original_string, CONTEXT_SEPARATOR)) |index| {
            self.context = self.original_string[0..index];
            self.original_string = self.original_string[index + 1 ..];
        } else {
            self.context = null;
        }
    }

    pub fn deinit(self: MoFileEntry, allocator: std.mem.Allocator) void {
        allocator.free(self._full_original_string);
        allocator.free(self.translation_string);
    }
};

const MoParser = struct {
    const MO_MAGIC = "\xde\x12\x04\x95";

    file: std.fs.File,

    const Self = @This();

    pub fn iterateEntries(self: Self, buffer: *MoFileEntry) !Iterator {
        try self.file.seekTo(0);
        const magic = try self.file.reader().readBytesNoEof(MO_MAGIC.len);
        if (!std.mem.eql(u8, magic, MO_MAGIC)) {
            return MoParserError.InvalidFormat;
        }

        try self.file.seekTo(8);
        const number_of_strings = try self.file.reader().readIntBig(u32);
        const original_string_table_offset = try self.file.reader().readIntBig(u32);
        const translation_string_table_offset = try self.file.reader().readIntBig(u32);

        return Iterator{
            .file = self.file,
            .number_of_strings = number_of_strings,
            .original_string_table_offset = original_string_table_offset,
            .translation_string_table_offset = translation_string_table_offset,
            .buffer = buffer,
        };
    }

    const Iterator = struct {
        allocator: std.mem.Allocator,
        i: u32 = 0,
        file: std.fs.File,
        number_of_strings: u32,
        original_string_table_offset: u32,
        translation_string_table_offset: u32,

        pub fn next(self: *Iterator) !?MoFileEntry {
            if (self.i >= self.number_of_strings) {
                return null;
            }
            defer self.i += 1;

            return MoFileEntry.init(
                try self.readString(self.original_string_table_offset, self.i),
                try self.readString(self.translation_string_table_offset, self.i),
            );
        }

        fn readString(self: *Iterator, table_offset: u32, index: u32) ![]const u8 {
            try self.file.seekTo(table_offset + index * 32);
            const string_size = try self.file.reader().readIntBig(u32);
            const string_offset = try self.file.reader().readIntBig(u32);

            try self.file.seekTo(string_offset);
            var string = try self.allocator.alloc(u8, string_size);
            return try self.file.reader().read(&string);
            // return try self.file.reader().read(string[0..string_size]);
        }
    };
};

fn main() void {
    const file = std.fs.openFileAbsolute("foo.mo", .{}) catch unreachable;
    var parser = MoParser{ .file = file };
    parser.readHeader() catch unreachable;
}
