const parse_raws = @import("parse_raws.zig");
const parse_mo = @import("parse_mo.zig");

test {
    _ = parse_raws;
}

pub fn main() !void {
    try parse_mo.print_mo("test_data/test.mo");
}
