const std = @import("std");
const zul = @import("zul");

const parse_raws = @import("parse_raws.zig");
const parse_mo = @import("parse_mo.zig");
const backup_manager = @import("backup_manager.zig");

test {
    _ = parse_raws;
    _ = parse_mo;
    _ = backup_manager;
}

pub fn main(init: std.process.Init) !void {
    // const gpa = init.gpa;
    // const io = init.io;
    const arena = init.arena.allocator();
    const args_iterator = init.minimal.args.iterate();
    var args = try zul.CommandLineArgs.parseFromIterator(arena, args_iterator);
    defer args.deinit();

    if (args.contains("print_mo")) {
        const print_mo_arg = args.get("print_mo") orelse {
            std.debug.print("print_mo arg not found\n", .{});
            return;
        };

        if (print_mo_arg.len == 0) {
            std.debug.print("print_mo arg is empty\n", .{});
            return;
        }

        std.debug.print("print_mo arg: {s}\n", .{print_mo_arg});
        try parse_mo.print_mo(print_mo_arg);
    }
}
