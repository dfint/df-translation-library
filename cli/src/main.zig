const std = @import("std");
const Io = std.Io;
const argsParser = @import("zig_args");

const print_mo = @import("print_mo.zig").print_mo;

const Verbs = union(enum) {
    print_mo: struct {
        path: ?[]const u8 = null,

        pub const shorthands = .{
            .p = "path",
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
        }
    }

    try stdout_writer.flush(); // Don't forget to flush!
}
