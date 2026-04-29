const std = @import("std");

const df_translation_library = @import("df_translation_library");
const parse_mo = df_translation_library.parse_mo;

/// Print contents of a MO file
pub fn print_mo(io: std.Io, allocator: std.mem.Allocator, mo_path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, mo_path, .{});
    defer file.close(io);

    const parser = try parse_mo.MoParser.init(io, file);
    const mo_header_info = parser.mo_header_info;
    std.debug.print("number of strings: {d}\n", .{mo_header_info.number_of_strings});
    std.debug.print("original string table offset: {d}\n", .{mo_header_info.original_string_table_offset});
    std.debug.print(
        "translation string table offset: {d}\n\n",
        .{mo_header_info.translation_string_table_offset},
    );

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
