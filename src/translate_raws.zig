const std = @import("std");

const Dictionary = @import("Dictionary.zig");
const TagPartsIterator = @import("parse_raws.zig").TagPartsIterator;
const RawTokenizer = @import("parse_raws.zig").StringTokenizer;
const getContextFromTag = @import("parse_raws.zig").getContextFromTag;

/// Translates complete RAW tags and preserves all text outside tags.
///
/// Looks up each tag as a whole in `dictionary`. Tags with a non-translatable
/// suffix can use a dictionary key ending in an empty part; the original
/// suffix is then retained. The caller owns the returned buffer.
pub fn translateRawFile(allocator: std.mem.Allocator, raw: []const u8, dictionary: *const Dictionary) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var header_context: ?[]const u8 = null;
    var context: ?[]const u8 = null;
    var tokenizer = RawTokenizer{ .raw = raw };
    while (tokenizer.next()) |token| {
        if (token.is_tag) {
            switch (getContextFromTag(token.text, header_context)) {
                .header => |header| {
                    // Just encountered file's header, e.g. [OBJECT:CREATURE].
                    header_context = header;
                    try output.appendSlice(allocator, token.text);
                    continue;
                },
                .object_definition => |object_definition| {
                    // We are inside an object definition, e.g. [CREATURE:DWARF], context will be CREATURE:DWARF for subsequent tags.
                    context = object_definition;
                    try output.appendSlice(allocator, token.text);
                    continue;
                },
                .regular_tag => {}, // All other tags are translated normally, using the current context if any.
            }

            const translation = try getTagTranslation(allocator, token.text, dictionary, context);
            defer if (translation) |value| allocator.free(value);
            try output.appendSlice(allocator, translation orelse token.text);
        } else {
            try output.appendSlice(allocator, token.text);
        }
    }

    return output.toOwnedSlice(allocator);
}

/// Reports whether a tag part contains text eligible for translation.
///
/// Matches the RAW translation rules: lowercase ASCII letters are translatable,
/// except for `n/a`; selected uppercase grammatical markers are also eligible.
fn isTranslatable(part: []const u8) bool {
    inline for (.{ "SINGULAR", "PLURAL", "STP", "NO_SUB", "NP" }) |special_tag| {
        if (std.mem.eql(u8, part, special_tag)) return true;
    }
    if (std.mem.eql(u8, part, "n/a")) return false;

    for (part) |char| {
        if (char >= 'a' and char <= 'z') return true;
    }
    return false;
}

/// Counts a tag's parts and finds the last translatable part index.
fn analyzeTag(tag: []const u8) struct {
    part_count: usize,
    last_translatable_part_index: ?usize,
} {
    var part_count: usize = 0;
    var last_translatable_part_index: ?usize = null;
    var part_index: usize = 0;
    var parts = TagPartsIterator{ .raw = tag };
    while (parts.next()) |part| : (part_index += 1) {
        if (part_index > 0 and isTranslatable(part)) {
            last_translatable_part_index = part_index;
        }
        part_count += 1;
    }
    return .{
        .part_count = part_count,
        .last_translatable_part_index = last_translatable_part_index,
    };
}

test "translate_raws: analyzeTag counts parts and finds the last translatable part" {
    const analysis = analyzeTag("[TAG:123:translated:456]");
    try std.testing.expectEqual(@as(usize, 4), analysis.part_count);
    try std.testing.expectEqual(@as(?usize, 2), analysis.last_translatable_part_index);
}

test "translate_raws: analyzeTag reports no translatable parts" {
    const analysis = analyzeTag("[TAG:123:n/a]");
    try std.testing.expectEqual(@as(usize, 3), analysis.part_count);
    try std.testing.expectEqual(@as(?usize, null), analysis.last_translatable_part_index);
}

/// Builds a lookup key ending after the last translatable part.
fn getPartialKey(
    allocator: std.mem.Allocator,
    tag: []const u8,
    last_part_index: usize,
) ![]u8 {
    var partial_key: std.ArrayList(u8) = .empty;
    errdefer partial_key.deinit(allocator);
    try partial_key.append(allocator, '[');
    var parts = TagPartsIterator{ .raw = tag };
    var part_index: usize = 0;
    var has_untranslatable_suffix = false;
    while (parts.next()) |part| : (part_index += 1) {
        if (part_index > last_part_index) {
            has_untranslatable_suffix = true;
            break;
        }
        if (part_index != 0) try partial_key.append(allocator, ':');
        try partial_key.appendSlice(allocator, part);
    }
    if (has_untranslatable_suffix) {
        try partial_key.appendSlice(allocator, ":]");
    } else {
        try partial_key.append(allocator, ']');
    }
    return try partial_key.toOwnedSlice(allocator);
}

test "translate_raws: getPartialKey closes key before an untranslatable suffix" {
    const allocator = std.testing.allocator;
    const partial_key = try getPartialKey(allocator, "[TAG:translated:123]", 1);
    defer allocator.free(partial_key);

    try std.testing.expectEqualStrings("[TAG:translated:]", partial_key);
}

test "translate_raws: getPartialKey detects multiple untranslatable suffix parts" {
    const allocator = std.testing.allocator;
    const partial_key = try getPartialKey(allocator, "[TAG:translated:123:456]", 1);
    defer allocator.free(partial_key);

    try std.testing.expectEqualStrings("[TAG:translated:]", partial_key);
}

test "translate_raws: getPartialKey closes key after the last part" {
    const allocator = std.testing.allocator;
    const partial_key = try getPartialKey(allocator, "[TAG:translated]", 1);
    defer allocator.free(partial_key);

    try std.testing.expectEqualStrings("[TAG:translated]", partial_key);
}

/// Counts translated parts when the partial translation has a final empty part.
fn getPartialTranslationPartCount(tag: []const u8) ?usize {
    if (tag.len < 3 or tag[0] != '[' or tag[tag.len - 1] != ']') return null;

    var part_count: usize = 0;
    var last_part: ?[]const u8 = null;
    var parts = TagPartsIterator{ .raw = tag };
    while (parts.next()) |part| {
        part_count += 1;
        last_part = part;
    }
    if (last_part == null or last_part.?.len != 0) return null;
    return part_count - 1;
}

test "translate_raws: getPartialTranslationPartCount counts parts before trailing empty part" {
    try std.testing.expectEqual(@as(?usize, 3), getPartialTranslationPartCount("[TAG:first:second:]"));
}

test "translate_raws: getPartialTranslationPartCount rejects missing trailing empty part" {
    try std.testing.expectEqual(@as(?usize, null), getPartialTranslationPartCount("[TAG:first:second]"));
}

/// Combines the translated prefix with the original tag's remaining parts.
fn getTranslatedTagFromPartialTranslation(
    allocator: std.mem.Allocator,
    partial_translation: []const u8,
    original_tag: []const u8,
    translated_prefix_len: usize,
) ![]u8 {
    var translated_tag: std.ArrayList(u8) = .empty;
    errdefer translated_tag.deinit(allocator);
    try translated_tag.append(allocator, '[');
    var translated_prefix = TagPartsIterator{ .raw = partial_translation };
    var translated_part_index: usize = 0;
    while (translated_prefix.next()) |part| : (translated_part_index += 1) {
        if (translated_part_index >= translated_prefix_len) break;
        if (translated_part_index != 0) try translated_tag.append(allocator, ':');
        try translated_tag.appendSlice(allocator, part);
    }

    var original_suffix = TagPartsIterator{ .raw = original_tag };
    var original_part_index: usize = 0;
    while (original_suffix.next()) |part| : (original_part_index += 1) {
        if (original_part_index < translated_prefix_len) continue;
        try translated_tag.append(allocator, ':');
        try translated_tag.appendSlice(allocator, part);
    }
    try translated_tag.append(allocator, ']');
    return try translated_tag.toOwnedSlice(allocator);
}

test "translate_raws: getTranslatedTagFromPartialTranslation preserves the original suffix" {
    const allocator = std.testing.allocator;
    const translated_tag = try getTranslatedTagFromPartialTranslation(
        allocator,
        "[TAG:translated:description:]",
        "[TAG:original:description:123:111]",
        3,
    );
    defer allocator.free(translated_tag);

    try std.testing.expectEqualStrings("[TAG:translated:description:123:111]", translated_tag);
}

/// Returns an owned translation of a tag, or null when no translation applies.
///
/// First looks up the complete tag. For tags ending in non-translatable parts,
/// looks up a key truncated after the last translatable part and preserves the
/// remaining original parts in the returned translation.
fn getTagTranslation(
    allocator: std.mem.Allocator,
    tag: []const u8,
    dictionary: *const Dictionary,
    context: ?[]const u8,
) !?[]u8 {
    if (tag.len < 2 or tag[0] != '[' or tag[tag.len - 1] != ']') {
        return null;
    }

    const analysis = analyzeTag(tag);
    if (analysis.part_count < 2 or analysis.last_translatable_part_index == null) return null;

    const last = analysis.last_translatable_part_index.?;
    const part_count = analysis.part_count;
    const first_colon = std.mem.indexOfScalarPos(u8, tag, 1, ':') orelse return null;
    const first_part = tag[1..first_colon];

    // If full translation exists, return it. Otherwise, look for a partial translation.
    var full_translation = try dictionary.get(.{ .original_string = tag, .context = context });
    if (full_translation == null and context != null) {
        full_translation = try dictionary.get(.{ .original_string = tag });
    }
    if (full_translation) |translation| {
        return try allocator.dupe(u8, translation);
    }

    if (last == part_count - 1) return null;

    const partial_key = try getPartialKey(allocator, tag, last);
    defer allocator.free(partial_key);

    var partial_translation = try dictionary.get(.{ .original_string = partial_key, .context = context });
    if (partial_translation == null and context != null) {
        partial_translation = try dictionary.get(.{ .original_string = partial_key });
    }
    const partial_value = partial_translation orelse return null;

    const translated_part_count = getPartialTranslationPartCount(partial_value) orelse return null;
    var translated_parts = TagPartsIterator{ .raw = partial_value };
    const translated_first_part = translated_parts.next() orelse return null;
    if (translated_part_count != last + 1 or !std.mem.eql(u8, translated_first_part, first_part)) {
        return null;
    }

    return try getTranslatedTagFromPartialTranslation(allocator, partial_value, tag, translated_part_count);
}

test "translate_raws: translate complete RAW tags and preserve non-translatable suffixes" {
    const allocator = std.testing.allocator;

    const Entry = struct { Dictionary.DictionaryKey, []const u8 };
    const ArrayIterator = struct {
        entries: []const Entry,
        index: usize = 0,

        /// Returns the next dictionary entry, or null when all entries are read.
        pub fn next(self: *@This()) ?Entry {
            if (self.index >= self.entries.len) return null;
            const entry = self.entries[self.index];
            self.index += 1;
            return entry;
        }
    };

    const entries = [_]Entry{
        .{ .{ .original_string = "Outside text" }, "Wrong outside" },
        .{ .{ .original_string = "Text 1" }, "Wrong individual translation" },
        .{ .{ .original_string = "[TEXT_SET:Text 1:Text 2]" }, "[TEXT_SET:Translated text:Translated two]" },
        .{ .{ .original_string = "[DESCRIPTION:Text 1]" }, "[DESCRIPTION:Translated description]" },
        .{
            .{ .original_string = "[TAG:translatable 1:translatable 2:]" },
            "[TAG:translated 1:translated 2:]",
        },
    };
    var iterator = ArrayIterator{ .entries = &entries };
    var dictionary = try Dictionary.loadFromIterator(allocator, &iterator);
    defer dictionary.deinit();

    const raw = "Outside text\n[TEXT_SET:Text 1:Text 2]\n[DESCRIPTION:Text 1]\n[TAG:translatable 1:translatable 2:123]\n[UNTAGGED]\n";
    const expected = "Outside text\n[TEXT_SET:Translated text:Translated two]\n[DESCRIPTION:Translated description]\n[TAG:translated 1:translated 2:123]\n[UNTAGGED]\n";
    const translated = try translateRawFile(allocator, raw, &dictionary);
    defer allocator.free(translated);

    try std.testing.expectEqualStrings(expected, translated);
}

test "translate_raws: translate tags with object context and context-free fallback" {
    const allocator = std.testing.allocator;

    const Entry = struct { Dictionary.DictionaryKey, []const u8 };
    const ArrayIterator = struct {
        entries: []const Entry,
        index: usize = 0,

        pub fn next(self: *@This()) ?Entry {
            if (self.index >= self.entries.len) return null;
            const entry = self.entries[self.index];
            self.index += 1;
            return entry;
        }
    };

    const entries = [_]Entry{
        .{ .{ .original_string = "[NAME:singular]", .context = "CREATURE:DWARF" }, "[NAME:contextual]" },
        .{ .{ .original_string = "[WORD:plural]" }, "[WORD:global]" },
        .{ .{ .original_string = "[DESCRIPTION:text:]", .context = "CREATURE:DWARF" }, "[DESCRIPTION:contextual:]" },
    };
    var iterator = ArrayIterator{ .entries = &entries };
    var dictionary = try Dictionary.loadFromIterator(allocator, &iterator);
    defer dictionary.deinit();

    const raw = "[OBJECT:CREATURE]\n[CREATURE:DWARF]\n[NAME:singular]\n[WORD:plural]\n[DESCRIPTION:text:123]\n";
    const expected = "[OBJECT:CREATURE]\n[CREATURE:DWARF]\n[NAME:contextual]\n[WORD:global]\n[DESCRIPTION:contextual:123]\n";
    const translated = try translateRawFile(allocator, raw, &dictionary);
    defer allocator.free(translated);

    try std.testing.expectEqualStrings(expected, translated);
}
