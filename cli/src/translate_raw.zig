const std = @import("std");

const df_translation_library = @import("df_translation_library");
const CsvParser = df_translation_library.parse_csv.CsvParser;
const CsvRow = df_translation_library.parse_csv.Row;
const Dictionary = df_translation_library.Dictionary;
const DictionaryKey = Dictionary.DictionaryKey;

const CsvDictionaryIterator = struct {
    parser: *CsvParser,
    current_row: ?CsvRow = null,

    pub fn deinit(self: *@This()) void {
        if (self.current_row) |*row| row.deinit();
    }

    pub fn next(self: *@This()) !?struct { DictionaryKey, []const u8 } {
        if (self.current_row) |*row| row.deinit();
        self.current_row = null;

        const row = try self.parser.next() orelse return null;
        self.current_row = row;
        const values = self.current_row.?.values;
        if (values.len < 3) return error.InvalidCsvDictionaryRow;

        return .{
            .{
                .original_string = values[0],
                .context = if (values[1].len == 0) null else values[1],
            },
            values[2],
        };
    }
};

/// Translates one RAW file using a CSV dictionary with original, context, and translation columns.
pub fn translateRawFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    raw_path: []const u8,
    dictionary_path: []const u8,
    output_path: []const u8,
) !void {
    const cwd = std.Io.Dir.cwd();
    const raw = try cwd.readFileAlloc(io, raw_path, allocator, .unlimited);
    defer allocator.free(raw);
    const csv = try cwd.readFileAlloc(io, dictionary_path, allocator, .unlimited);
    defer allocator.free(csv);

    var csv_parser = CsvParser{ .allocator = allocator, .input = csv };
    var iterator = CsvDictionaryIterator{ .parser = &csv_parser };
    defer iterator.deinit();
    var dictionary = try Dictionary.loadFromIterator(allocator, &iterator);
    defer dictionary.deinit();

    const translated = try df_translation_library.translate_raws.translateRawFile(
        allocator,
        raw,
        &dictionary,
    );
    defer allocator.free(translated);

    const output_file = try cwd.createFile(io, output_path, .{ .truncate = true });
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, translated);
}
