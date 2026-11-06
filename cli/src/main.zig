const std = @import("std");
const Io = std.Io;
const argsParser = @import("zig_args");

const print_mo = @import("print_mo.zig").print_mo;
const translate_raw = @import("translate_raw.zig").translateRawFile;

const Verbs = union(enum) {
    print_mo: struct {
        path: ?[]const u8 = null,

        pub const shorthands = .{
            .p = "path",
        };
    },
    translate_raw: struct {
        raw: ?[]const u8 = null,
        dictionary: ?[]const u8 = null,
        output: ?[]const u8 = null,

        pub const shorthands = .{
            .r = "raw",
            .d = "dictionary",
            .o = "output",
        };
    },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const options = try argsParser.parseWithVerbForCurrentProcess(struct {}, Verbs, init, .print);
    defer options.deinit();

    if (options.verb) |verb| {
        switch (verb) {
            .print_mo => |opts| {
                std.debug.print("print_mo\n", .{});
                if (opts.path) |path| {
                    std.debug.print("path={s}\n", .{path});
                    try print_mo(io, init.gpa, path);
                }
            },
            .translate_raw => |opts| {
                const raw_path = opts.raw orelse return error.MissingRawPath;
                const dictionary_path = opts.dictionary orelse return error.MissingDictionaryPath;
                const output_path = opts.output orelse return error.MissingOutputPath;
                try translate_raw(io, init.gpa, raw_path, dictionary_path, output_path);
            },
        }
    }

    try stdout_writer.flush(); // Don't forget to flush!
}
