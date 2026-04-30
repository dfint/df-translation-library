//! Backup manager: creates a backup of a file in the current directory, can restore file contents from backup.

const std = @import("std");

const testing_utils = @import("testing_utils.zig");
const TestDataEntry = testing_utils.TestDataEntry;

io: std.Io,
allocator: std.mem.Allocator,
backup_dir: std.Io.Dir,
source_filename: []const u8,
backup_filename_buffer: std.ArrayList(u8),

const Self = @This();

/// Initialize backup manager
pub fn init(io: std.Io, allocator: std.mem.Allocator, directory: std.Io.Dir, filename: []const u8) !Self {
    return .{
        .io = io,
        .allocator = allocator,
        .source_filename = filename,
        .backup_dir = directory,
        .backup_filename_buffer = try Self.getBackupFileName(allocator, filename),
    };
}

/// Deinitialize backup manager.
pub fn deinit(self: *Self) void {
    self.backup_filename_buffer.deinit(self.allocator);
}

/// Get backup file name from a file name (e.g. "file_name.txt" -> "file_name.bak").
fn getBackupFileName(allocator: std.mem.Allocator, file_name: []const u8) !std.ArrayList(u8) {
    var backup_file_name: std.ArrayList(u8) = .empty;
    try backup_file_name.appendSlice(allocator, Self.getFileNameStem(file_name));
    try backup_file_name.appendSlice(allocator, ".bak");
    return backup_file_name;
}

/// Remove extension from a file name. Only last extension is removed (split by the last "." character).
fn getFileNameStem(file_name: []const u8) []const u8 {
    const last_dot_index = std.mem.lastIndexOf(u8, file_name, ".") orelse file_name.len;
    return if (last_dot_index > 0) file_name[0..last_dot_index] else file_name;
}

/// Create backup of a file.
pub fn backup(self: Self) !void {
    self.backup_dir.access(
        self.io,
        self.backup_filename_buffer.items,
        .{ .read = true },
    ) catch |err| switch (err) {
        error.FileNotFound => {
            try self.backup_dir.copyFile(
                self.source_filename,
                self.backup_dir,
                self.backup_filename_buffer.items,
                self.io,
                .{},
            );
        },
        else => return err,
    };
}

/// Restore file from backup.
pub fn restore(self: Self) !void {
    _ = try self.backup_dir.updateFile(
        self.io,
        self.backup_filename_buffer.items,
        self.backup_dir,
        self.source_filename,
        .{},
    );
}

/// Delete backup file. Dangerous, don't use it in production code.
fn deleteBackup(self: Self) !void {
    try self.backup_dir.deleteFile(self.io, self.backup_filename_buffer.items);
}

test "BackupManager.getBackupFileName" {
    const allocator = std.testing.allocator;

    const data = [_]TestDataEntry([]const u8, []const u8){
        .{ .input = "test.txt", .expected = "test.bak" },
        .{ .input = "test", .expected = "test.bak" },
        .{ .input = "some.file.txt", .expected = "some.file.bak" },
        .{ .input = ".somefile", .expected = ".somefile.bak" },
    };

    for (data) |row| {
        var backup_path = try Self.getBackupFileName(allocator, row.input);
        defer backup_path.deinit(allocator);
        try std.testing.expectEqualStrings(row.expected, backup_path.items);
    }
}

test "BackupManager.getFileNameStem" {
    const data = [_]TestDataEntry([]const u8, []const u8){
        .{ .input = "test.txt", .expected = "test" },
        .{ .input = "test", .expected = "test" },
        .{ .input = "some.file.txt", .expected = "some.file" },
        .{ .input = ".somefile", .expected = ".somefile" },
    };

    for (data) |row| {
        const backup_name = Self.getFileNameStem(row.input);
        try std.testing.expectEqualStrings(row.expected, backup_name);
    }
}

test "BackupManager: full test" {
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();

    const dir_name = "test_dir";
    const source_file_name = "file.txt";
    const file_contents = "Hello, world!";

    cwd.createDir(io, dir_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Ignore
        else => return err,
    };

    const directory = try cwd.openDir(io, dir_name, .{});

    {
        const file = try directory.createFile(io, source_file_name, .{ .truncate = true });
        defer file.close(io);

        var writer = file.writer(io, &.{});
        try writer.interface.writeAll(file_contents);
        try writer.interface.flush();
    }
    defer directory.deleteFile(io, source_file_name) catch unreachable;

    const allocator = std.testing.allocator;
    var backup_manager = try Self.init(io, allocator, directory, source_file_name);
    defer {
        backup_manager.deleteBackup() catch unreachable;
        backup_manager.deinit();
    }

    const backup_file_name = backup_manager.backup_filename_buffer.items;

    try backup_manager.backup();

    const actual_content = try directory.readFileAlloc(
        io,
        backup_file_name,
        allocator,
        .unlimited,
    );
    defer allocator.free(actual_content);

    try std.testing.expectEqualStrings(file_contents, actual_content);

    {
        const file = try directory.openFile(io, source_file_name, .{ .mode = .write_only });
        defer file.close(io);
        try file.writeStreamingAll(io, "");
    }

    try backup_manager.restore();
    const restored_content = try directory.readFileAlloc(
        io,
        source_file_name,
        allocator,
        .unlimited,
    );
    defer allocator.free(restored_content);

    try std.testing.expectEqualStrings(file_contents, restored_content);
}
