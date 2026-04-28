const std = @import("std");
const Io = std.Io;
const argsParser = @import("zig_args");

// const parse_raws = @import("parse_raws.zig");
// const parse_mo = @import("parse_mo.zig");
// const backup_manager = @import("backup_manager.zig");

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
                }
            },
        }
    }

    // if (args.contains("print_mo")) {
    //     const print_mo_arg = args.get("print_mo") orelse {
    //         std.debug.print("print_mo arg not found\n", .{});
    //         return;
    //     };

    //     if (print_mo_arg.len == 0) {
    //         std.debug.print("print_mo arg is empty\n", .{});
    //         return;
    //     }

    //     std.debug.print("print_mo arg: {s}\n", .{print_mo_arg});
    //     try parse_mo.print_mo(print_mo_arg);
    // }

    try stdout_writer.flush(); // Don't forget to flush!
}
