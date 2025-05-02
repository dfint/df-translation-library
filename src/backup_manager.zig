const std = @import("std");

const BackupManager = struct {
    allocator: std.mem.Allocator,
    backup_dir: std.fs.Dir,
    source_filename: []const u8,
    backup_filename_buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, directory: std.fs.Dir, filename: []const u8) !Self {
        return BackupManager{
            .allocator = allocator,
            .source_filename = filename,
            .backup_dir = directory,
            .backup_filename_buffer = try Self.getBackupFileName(allocator, filename),
        };
    }

    pub fn deinit(self: *Self) void {
        self.backup_filename_buffer.deinit();
    }

    fn getBackupFileName(allocator: std.mem.Allocator, file_name: []const u8) !std.ArrayList(u8) {
        var backup_file_name = std.ArrayList(u8).init(allocator);
        try backup_file_name.appendSlice(Self.getFileNameStem(file_name));
        try backup_file_name.appendSlice(".bak");
        return backup_file_name;
    }

    fn getFileNameStem(file_name: []const u8) []const u8 {
        const last_dot_index = std.mem.lastIndexOf(u8, file_name, ".") orelse file_name.len;
        return if (last_dot_index > 0) file_name[0..last_dot_index] else file_name;
    }

    pub fn backup(self: Self) !void {
        self.backup_dir.access(
            self.backup_filename_buffer.items,
            .{ .mode = .read_only },
        ) catch |err| switch (err) {
            error.FileNotFound => {
                try self.backup_dir.copyFile(
                    self.source_filename,
                    self.backup_dir,
                    self.backup_filename_buffer.items,
                    .{},
                );
            },
            else => return err,
        };
    }

    pub fn restore(self: Self) !void {
        _ = try self.backup_dir.updateFile(
            self.backup_filename_buffer.items,
            self.backup_dir,
            self.source_filename,
            .{},
        );
    }

    pub fn deleteBackup(self: Self) !void {
        try self.backup_dir.deleteFile(self.backup_filename_buffer.items);
    }
};

const TestDataEntry = struct {
    input: []const u8,
    expected: []const u8,
};

test "getBackupFileName" {
    const allocator = std.testing.allocator;

    const data = [_]TestDataEntry{
        TestDataEntry{ .input = "test.txt", .expected = "test.bak" },
        TestDataEntry{ .input = "test", .expected = "test.bak" },
        TestDataEntry{ .input = "some.file.txt", .expected = "some.file.bak" },
        TestDataEntry{ .input = ".somefile", .expected = ".somefile.bak" },
    };

    for (data) |row| {
        const backup_path = try BackupManager.getBackupFileName(allocator, row.input);
        defer backup_path.deinit();
        try std.testing.expectEqualStrings(row.expected, backup_path.items);
    }
}

test "getFileNameStem" {
    const data = [_]TestDataEntry{
        TestDataEntry{ .input = "test.txt", .expected = "test" },
        TestDataEntry{ .input = "test", .expected = "test" },
        TestDataEntry{ .input = "some.file.txt", .expected = "some.file" },
        TestDataEntry{ .input = ".somefile", .expected = ".somefile" },
    };

    for (data) |row| {
        const backup_name = BackupManager.getFileNameStem(row.input);
        try std.testing.expectEqualStrings(row.expected, backup_name);
    }
}

test "test backup" {
    const dir_name = "test_dir";
    const source_file_name = "file.txt";
    const file_contents = "Hello, world!";

    std.fs.cwd().makeDir(dir_name) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Ignore
        else => return err,
    };

    const directory = try std.fs.cwd().openDir(dir_name, .{});

    {
        const file = try directory.createFile(source_file_name, .{});
        defer file.close();
        try file.writeAll(file_contents);
    }
    defer directory.deleteFile(source_file_name) catch unreachable;

    const allocator = std.testing.allocator;
    var backup_manager = try BackupManager.init(allocator, directory, source_file_name);
    defer {
        backup_manager.deleteBackup() catch unreachable;
        backup_manager.deinit();
    }

    const backup_file_name = backup_manager.backup_filename_buffer.items;

    try backup_manager.backup();

    const actual_content = try directory.readFileAlloc(
        allocator,
        backup_file_name,
        std.math.maxInt(usize),
    );
    defer allocator.free(actual_content);

    try std.testing.expectEqualStrings(file_contents, actual_content);

    {
        const file = try directory.openFile(source_file_name, .{ .mode = .write_only });
        defer file.close();
        try file.writeAll("");
    }

    try backup_manager.restore();
    const restored_content = try directory.readFileAlloc(
        allocator,
        source_file_name,
        std.math.maxInt(usize),
    );
    defer allocator.free(restored_content);

    try std.testing.expectEqualStrings(file_contents, restored_content);
}
