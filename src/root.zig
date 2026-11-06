pub const parse_raws = @import("parse_raws.zig");
pub const parse_csv = @import("parse_csv.zig");
pub const parse_mo = @import("parse_mo.zig");
pub const translate_raws = @import("translate_raws.zig");
const BackupManager = @import("BackupManager.zig");

test "fake root test" {
    _ = parse_raws;
    _ = parse_csv;
    _ = parse_mo;
    _ = translate_raws;
    _ = BackupManager;
}

// TODO: replace with exported dll functions
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}
