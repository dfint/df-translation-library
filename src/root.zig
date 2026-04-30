const std = @import("std");
const testing = std.testing;

pub const parse_raws = @import("parse_raws.zig");
pub const parse_mo = @import("parse_mo.zig");
const BackupManager = @import("BackupManager.zig");

test "fake root test" {
    _ = parse_raws;
    _ = parse_mo;
    _ = BackupManager;
}

// TODO: replace with exported dll functions
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}
