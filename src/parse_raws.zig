const std = @import("std");
const zul = @import("zul");

const TagPartsIterator = struct {
    raw: []const u8,
    pos: usize = 0,

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
    var iter = TagPartsIterator{ .raw = "[ab:cd:de:fe]" };
    try std.testing.expectEqualStrings("ab", iter.next().?);
    try std.testing.expectEqualStrings("cd", iter.next().?);
    try std.testing.expectEqualStrings("de", iter.next().?);
    try std.testing.expectEqualStrings("fe", iter.next().?);
    try std.testing.expectEqual(null, iter.next());
}

const Token = struct {
    text: []const u8,
    is_tag: bool,
};

const LineTokenizer = struct {
    raw: []const u8,
    pos: usize = 0,
    token: Token = undefined,

    pub fn next(self: *LineTokenizer) ?Token {
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
        self.token = .{
            .text = self.raw[start..end],
            .is_tag = is_tag,
        };

        return self.token;
    }
};

test "LineTokenizer" {
    var iter = LineTokenizer{ .raw = "   [TAG1:cd:de:fe]    [TAG2]a" };

    try zul.testing.expectEqual(
        Token{ .text = "   ", .is_tag = false },
        iter.next().?,
    );

    try zul.testing.expectEqual(
        Token{ .text = "[TAG1:cd:de:fe]", .is_tag = true },
        iter.next().?,
    );

    try zul.testing.expectEqual(
        Token{ .text = "    ", .is_tag = false },
        iter.next().?,
    );

    try zul.testing.expectEqual(
        Token{ .text = "[TAG2]", .is_tag = true },
        iter.next().?,
    );

    try zul.testing.expectEqual(
        Token{ .text = "a", .is_tag = false },
        iter.next().?,
    );

    try std.testing.expectEqualDeep(null, iter.next());
}

test "LineTokenizer multiline" {
    const data =
        \\[TAG1:cd:de:fe]
        \\[TAG2]a
        \\[TAG3]b
        \\[TAG4]c
    ;

    var parser = LineTokenizer{ .raw = data };

    try zul.testing.expectEqual(
        Token{ .text = "[TAG1:cd:de:fe]", .is_tag = true },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "\n", .is_tag = false },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "[TAG2]", .is_tag = true },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "a\n", .is_tag = false },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "[TAG3]", .is_tag = true },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "b\n", .is_tag = false },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "[TAG4]", .is_tag = true },
        parser.next().?,
    );
    try zul.testing.expectEqual(
        Token{ .text = "c", .is_tag = false },
        parser.next().?,
    );
    try std.testing.expectEqual(null, parser.next());
}
