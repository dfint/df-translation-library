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

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const allocator = da.allocator();

    var args = try zul.CommandLineArgs.parse(allocator);
    defer args.deinit();

    if (args.count() == 0) {
        std.debug.print("No arguments passed\n", .{});
        return;
    }

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
