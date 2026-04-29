const std = @import("std");
const testing = std.testing;

pub const parse_raws = @import("parse_raws.zig");
pub const parse_mo = @import("parse_mo.zig");
const backup_manager = @import("backup_manager.zig");

test {
    _ = parse_raws;
    _ = parse_mo;
    _ = backup_manager;
}

// TODO: replace with exported dll functions
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
