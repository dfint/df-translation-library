const std = @import("std");

const utils = @import("utils.zig");

/// Iterates over colon-separated fields in a bracketed RAW tag without allocating.
///
/// Empty fields, including a final empty field, are returned as empty slices.
pub const TagPartsIterator = struct {
    raw: []const u8,
    pos: usize = 0,

    /// Returns the next field as a slice of the original tag, or null when done.
    pub fn next(self: *TagPartsIterator) ?[]const u8 {
        if (self.pos >= self.raw.len) {
            return null;
        }

        if (self.pos == 0 and self.raw[self.pos] == '[') {
            self.pos += 1;
        }

        if (self.pos >= self.raw.len) return null;
        if (self.raw[self.pos] == ']') {
            const empty_field = self.raw[self.pos..self.pos];
            self.pos += 1;
            return empty_field;
        }

        const start = self.pos;
        while (self.pos < self.raw.len and self.raw[self.pos] != ':' and self.raw[self.pos] != ']') {
            self.pos += 1;
        }
        const end = self.pos;
        if (self.pos < self.raw.len) self.pos += 1;
        return self.raw[start..end];
    }
};

pub const ContextTagInfo = union(enum) {
    header: ?[]const u8,
    object_definition: []const u8,
    regular_tag,
};

/// Reports whether a tag name identifies the current object definition.
pub fn isObjectDefinition(tag_name: []const u8, context: []const u8) bool {
    // [CREATURE:DWARF] -> object name matches the tag name exactly
    if (std.mem.eql(u8, tag_name, context)) return true;

    // [OBJECT:ITEM] + [ITEM_TOOL:EXAMPLE DRUM BODY] -> ITEM tag names may extend the object name.
    // [OBJECT:BUILDING] + [BUILDING_WORKSHOP:SOAP_MAKER] -> BUILDING tag names may extend the object name.
    if ((std.mem.eql(u8, context, "ITEM") or std.mem.eql(u8, context, "BUILDING")) and
        std.mem.startsWith(u8, tag_name, context))
    {
        return true;
    }

    // [OBJECT:DESCRIPTOR_COLOR] + [COLOR:AMBER] -> tag name matches the object name suffix.
    return context.len > tag_name.len and
        std.mem.endsWith(u8, context, tag_name) and
        context[context.len - tag_name.len - 1] == '_';
}

test "parse_raws: isObjectDefinition matches object tag names" {
    try std.testing.expect(isObjectDefinition("CREATURE", "CREATURE"));
    try std.testing.expect(isObjectDefinition("ITEM_TOOL", "ITEM"));
    try std.testing.expect(isObjectDefinition("BUILDING_WORKSHOP", "BUILDING"));
    try std.testing.expect(isObjectDefinition("COLOR", "DESCRIPTOR_COLOR"));
    try std.testing.expect(!isObjectDefinition("NAME", "CREATURE"));
}

/// Returns the current context based on the tag and object name.
pub fn getContextFromTag(tag: []const u8, context: ?[]const u8) ContextTagInfo {
    var parts = TagPartsIterator{ .raw = tag };
    const tag_name = parts.next() orelse return .regular_tag;

    if (std.mem.eql(u8, tag_name, "OBJECT")) {
        // [OBJECT:CREATURE] -> .header = "CREATURE"
        return .{ .header = parts.next() };
    }

    if (context) |name| {
        if (isObjectDefinition(tag_name, name)) {
            // The tag contents, without brackets, become the context.
            return .{ .object_definition = tag[1 .. tag.len - 1] };
        }
    }

    // Tags that do not identify an object definition are translated normally.
    return .regular_tag;
}

test "parse_raws: getContextFromTag tracks object header and definition" {
    const context = getContextFromTag("[OBJECT:CREATURE]", null);
    try std.testing.expectEqualStrings("CREATURE", context.header.?);

    const object_definition = getContextFromTag("[CREATURE:DWARF]", context.header.?);
    try std.testing.expectEqualStrings("CREATURE:DWARF", object_definition.object_definition);

    const regular_tag = getContextFromTag("[NAME:singular]", context.header.?);
    try std.testing.expect(regular_tag == .regular_tag);
}

test "TagPartsIterator" {
    const allocator = std.testing.allocator;
    const input = "[ab:cd:de:fe]";
    const expected = [_][]const u8{ "ab", "cd", "de", "fe" };

    var iter = TagPartsIterator{ .raw = input };
    var results = try utils.collectIterator([]const u8, allocator, &iter);
    defer results.deinit(allocator);

    try std.testing.expectEqualDeep(&expected, results.items);
}

test "TagPartsIterator: empty final field" {
    const allocator = std.testing.allocator;
    const input = "[TAG:text:]";
    const expected = [_][]const u8{ "TAG", "text", "" };

    var iter = TagPartsIterator{ .raw = input };
    var results = try utils.collectIterator([]const u8, allocator, &iter);
    defer results.deinit(allocator);

    try std.testing.expectEqualDeep(&expected, results.items);
}

/// Token structure.
pub const Token = struct {
    text: []const u8,
    is_tag: bool,
};

/// Tokenizer of raw file contents.
pub const StringTokenizer = struct {
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
