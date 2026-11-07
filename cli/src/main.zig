const std = @import("std");
const argsParser = @import("zig_args");

const translate_raw = @import("translate_raw.zig").translateRawFile;

const Verbs = union(enum) {
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

    const options = try argsParser.parseWithVerbForCurrentProcess(struct {}, Verbs, init, .print);
    defer options.deinit();

    if (options.verb) |verb| {
        switch (verb) {
            .translate_raw => |opts| {
                const raw_path = opts.raw orelse return error.MissingRawPath;
                const dictionary_path = opts.dictionary orelse return error.MissingDictionaryPath;
                const output_path = opts.output orelse return error.MissingOutputPath;
                try translate_raw(io, init.gpa, raw_path, dictionary_path, output_path);
            },
        }
    }
}
