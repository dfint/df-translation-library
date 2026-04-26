const std = @import("std");
const Io = std.Io;
const zig_cli = @import("zig-cli");

// const parse_raws = @import("parse_raws.zig");
// const parse_mo = @import("parse_mo.zig");
// const backup_manager = @import("backup_manager.zig");

const app_spec = zig_cli.app(.{
    .name = "df_translation_library_cli",
    .description = "CLI for the DF Translation Library",
    .commands = .{
        .print_mo = zig_cli.command(.{
            .description = "Print contents of mo file",
            .options = .{
                .file_path = zig_cli.option(
                    []const u8,
                    .{
                        .long = "path",
                        .short = 'p',
                        .description = "MO file path",
                        // .group = "api",
                    },
                    "file.mo",
                ),
            },
        }),
    },
});

pub fn main(init: std.process.Init) !void {
    // const arena: std.mem.Allocator = init.arena.allocator();

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    const args = zig_cli.parse(app_spec, init.minimal.args, std.heap.page_allocator) catch |err| switch (err) {
        error.HelpRequested, error.VersionRequested => std.process.exit(0),
        else => std.process.exit(1),
    };

    switch (args) {
        .print_mo => |opts| {
            std.debug.print("print_mo\n", .{});
            std.debug.print("file_path={d}\n", .{
                opts.file_path,
            });
        },
    }

    // var args_iterator = init.minimal.args.iterate();
    // defer args.deinit();

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
