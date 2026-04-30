const std = @import("std");

const utils = @import("utils.zig");

/// Iterator over tag parts: [abc:cde:fgh] -> "abc", "cde", "fgh"
const TagPartsIterator = struct {
    raw: []const u8,
    pos: usize = 0,

    /// Get the next value from the iterator
    pub fn next(self: *TagPartsIterator) ?[]const u8 {
        if (self.pos >= self.raw.len) {
            return null;
        }

        if (self.raw[self.pos] == ']') {
            return null;
        }

        if (self.raw[self.pos] == '[') {
            self.pos += 1;
        }

        const start = self.pos;
        while (self.pos < self.raw.len and self.raw[self.pos] != ':' and self.raw[self.pos] != ']') {
            self.pos += 1;
        }
        const end = self.pos;
        self.pos += 1;
        return self.raw[start..end];
    }
};

test "TagPartsIterator" {
    const allocator = std.testing.allocator;
    const input = "[ab:cd:de:fe]";
    const expected = [_][]const u8{ "ab", "cd", "de", "fe" };

    var iter = TagPartsIterator{ .raw = input };
    var results = try utils.collectIterator([]const u8, allocator, &iter);
    defer results.deinit(allocator);

    try std.testing.expectEqualDeep(&expected, results.items);
}

/// Token structure.
const Token = struct {
    text: []const u8,
    is_tag: bool,
};

/// Tokenizer of raw file contents.
const StringTokenizer = struct {
    raw: []const u8,
    pos: usize = 0,

    /// Get the next token from a raw file.
    pub fn next(self: *StringTokenizer) ?Token {
        if (self.pos >= self.raw.len) {
            return null;
        }

        var is_tag: bool = false;
        const start = self.pos;
        if (self.raw[start] == '[') {
            is_tag = true;
            self.pos += 1;
        }

        while (self.pos < self.raw.len) {
            if (is_tag) {
                if (self.raw[self.pos] == ']') {
                    self.pos += 1;
                    break;
                }
            } else {
                if (self.raw[self.pos] == '[') {
                    break;
                }
            }
            self.pos += 1;
        }

        const end = self.pos;

        return .{
            .text = self.raw[start..end],
            .is_tag = is_tag,
        };
    }
};

test "StringTokenizer: one line" {
    const allocator = std.testing.allocator;
    const input = "   [TAG1:cd:de:fe]    [TAG2]a";
    const expected = [_]Token{
        .{ .text = "   ", .is_tag = false },
        .{ .text = "[TAG1:cd:de:fe]", .is_tag = true },
        .{ .text = "    ", .is_tag = false },
        .{ .text = "[TAG2]", .is_tag = true },
        .{ .text = "a", .is_tag = false },
    };

    var iter = StringTokenizer{ .raw = input };
    var results = try utils.collectIterator(Token, allocator, &iter);
    defer results.deinit(allocator);

    try std.testing.expectEqualDeep(&expected, results.items);
}

test "StringTokenizer: multiline" {
    const allocator = std.testing.allocator;
    const input =
        \\[TAG1:cd:de:fe]
        \\[TAG2]a
        \\[TAG3]b
        \\[TAG4]c
    ;
    const expected = [_]Token{
        .{ .text = "[TAG1:cd:de:fe]", .is_tag = true },
        .{ .text = "\n", .is_tag = false },
        .{ .text = "[TAG2]", .is_tag = true },
        .{ .text = "a\n", .is_tag = false },
        .{ .text = "[TAG3]", .is_tag = true },
        .{ .text = "b\n", .is_tag = false },
        .{ .text = "[TAG4]", .is_tag = true },
        .{ .text = "c", .is_tag = false },
    };

    var parser = StringTokenizer{ .raw = input };
    var results = try utils.collectIterator(Token, allocator, &parser);
    defer results.deinit(allocator);

    try std.testing.expectEqualDeep(&expected, results.items);
}

test "StringTokenizer: parse raw file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const file_path = "test_data/object_creature.txt";
    const cwd = std.Io.Dir.cwd();
    const file_contents = try cwd.readFileAlloc(io, file_path, allocator, .unlimited);
    defer allocator.free(file_contents);

    var iterator = StringTokenizer{ .raw = file_contents };
    while (iterator.next()) |token| {
        if (token.is_tag) {
            try std.testing.expect(token.text.len > 0 and
                token.text[0] == '[' and
                token.text[token.text.len - 1] == ']');
        }
    }
}
