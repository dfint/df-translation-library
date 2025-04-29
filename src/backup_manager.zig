const std = @import("std");

// 1. Check if backup exists
// 2. If doesn't exist, than create it
// 3. Return original path

const BackupError = error{
    BackupMissing,
};

const BackupManager = struct {
    allocator: std.mem.Allocator,
    backup_path: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Self {
        return BackupManager{
            .allocator = allocator,
            .backup_path = Self.getBackupPath(allocator, filename),
        };
    }

    pub fn deinit(self: *Self) void {
        self.backup_path.deinit();
    }

    fn getBackupPath(allocator: std.mem.Allocator, file_path: []const u8) !std.ArrayList(u8) {
        var backup_path = std.ArrayList(u8).init(allocator);

        const last_slash_index = std.mem.lastIndexOfAny(u8, file_path, "/\\");
        var file_name: []const u8 = undefined;
        if (last_slash_index) |lsi| {
            try backup_path.appendSlice(file_path[0 .. lsi + 1]);
            file_name = file_path[lsi + 1 .. file_path.len];
        } else {
            file_name = file_path;
        }

        const last_dot_index = std.mem.lastIndexOf(u8, file_name, ".") orelse file_name.len;
        try backup_path.appendSlice(file_name[0..last_dot_index]);
        try backup_path.appendSlice(".bak");
        return backup_path;
    }
    
    pub fn backup(self: Self) !void {
        _ = self;
    }
    
    pub fn restore(self: Self) BackupError.BackupMissing!void {
        _ = self;
    }
    
    pub fn deleteBackup(self: Self) !void {
        _ = self;
    }
};

test "getBackupPath" {
    const TestDataEntry = struct {
        input: []const u8,
        expected: []const u8,
    };

    const allocator = std.testing.allocator;

    const data = [_]TestDataEntry{
        TestDataEntry{ .input = "dir/test.txt", .expected = "dir/test.bak" },
        TestDataEntry{ .input = "/test.txt", .expected = "/test.bak" },
        TestDataEntry{ .input = "dir\\test.txt", .expected = "dir\\test.bak" },
        TestDataEntry{ .input = "test.txt", .expected = "test.bak" },
        TestDataEntry{ .input = "dir/test", .expected = "dir/test.bak" },
        TestDataEntry{ .input = "di.r/test.txt", .expected = "di.r/test.bak" },
    };

    for (data) |row| {
        const backup_path = try BackupManager.getBackupPath(allocator, row.input);
        defer backup_path.deinit();
        try std.testing.expectEqualStrings(row.expected, backup_path.items);
    }
}
