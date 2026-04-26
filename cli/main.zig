const std = @import("std");
const Io = std.Io;

// const parse_raws = @import("parse_raws.zig");
// const parse_mo = @import("parse_mo.zig");
// const backup_manager = @import("backup_manager.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

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
