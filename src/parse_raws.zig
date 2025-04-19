const std = @import("std");

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
