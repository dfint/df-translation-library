const std = @import("std");

const CsvError = error{
    UnterminatedQuotedValue,
    QuoteInUnquotedValue,
    InvalidCharacterAfterQuote,
};

/// A CSV row. The caller owns the row and must call `deinit` when finished.
pub const Row = struct {
    allocator: std.mem.Allocator,
    values: [][]u8,

    pub fn deinit(self: *Row) void {
        for (self.values) |value| self.allocator.free(value);
        self.allocator.free(self.values);
    }
};

/// Iterates over CSV rows. Commas and newlines inside quoted values are preserved,
/// and doubled quotes inside quoted values are decoded to a single quote.
pub const CsvParser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize = 0,

    /// Returns the next row, or null when the input is exhausted.
    pub fn next(self: *CsvParser) !?Row {
        if (self.position >= self.input.len) return null;

        var values: std.ArrayList([]u8) = .empty;
        errdefer {
            for (values.items) |value| self.allocator.free(value);
            values.deinit(self.allocator);
        }

        while (true) {
            const value = try self.parseValue();
            values.append(self.allocator, value) catch |err| {
                self.allocator.free(value);
                return err;
            };

            if (self.position == self.input.len) break;
            switch (self.input[self.position]) {
                ',' => self.position += 1,
                '\n', '\r' => {
                    self.consumeNewline();
                    break;
                },
                else => return CsvError.InvalidCharacterAfterQuote,
            }
        }

        return .{
            .allocator = self.allocator,
            .values = try values.toOwnedSlice(self.allocator),
        };
    }

    fn parseValue(self: *CsvParser) ![]u8 {
        var value: std.ArrayList(u8) = .empty;
        errdefer value.deinit(self.allocator);

        if (self.position < self.input.len and self.input[self.position] == '"') {
            self.position += 1;
            while (self.position < self.input.len) {
                const char = self.input[self.position];
                if (char == '"') {
                    if (self.position + 1 < self.input.len and self.input[self.position + 1] == '"') {
                        try value.append(self.allocator, '"');
                        self.position += 2;
                        continue;
                    }
                    self.position += 1;
                    return try value.toOwnedSlice(self.allocator);
                }
                try value.append(self.allocator, char);
                self.position += 1;
            }
            return CsvError.UnterminatedQuotedValue;
        }

        while (self.position < self.input.len and self.input[self.position] != ',' and
            self.input[self.position] != '\n' and self.input[self.position] != '\r')
        {
            if (self.input[self.position] == '"') return CsvError.QuoteInUnquotedValue;
            try value.append(self.allocator, self.input[self.position]);
            self.position += 1;
        }
        return try value.toOwnedSlice(self.allocator);
    }

    fn consumeNewline(self: *CsvParser) void {
        if (self.input[self.position] == '\r' and
            self.position + 1 < self.input.len and self.input[self.position + 1] == '\n')
        {
            self.position += 2;
        } else {
            self.position += 1;
        }
    }
};

test "parse_csv: parses quoted rows and doubled quotes" {
    const allocator = std.testing.allocator;
    var parser = CsvParser{
        .allocator = allocator,
        .input = "\"first\",\"comma, value\",\"say \"\"hello\"\"\"\r\n\"next\",\"row\",\"\"",
    };

    var first = (try parser.next()).?;
    defer first.deinit();
    try std.testing.expectEqual(@as(usize, 3), first.values.len);
    try std.testing.expectEqualStrings("first", first.values[0]);
    try std.testing.expectEqualStrings("comma, value", first.values[1]);
    try std.testing.expectEqualStrings("say \"hello\"", first.values[2]);

    var second = (try parser.next()).?;
    defer second.deinit();
    try std.testing.expectEqualStrings("next", second.values[0]);
    try std.testing.expectEqualStrings("row", second.values[1]);
    try std.testing.expectEqualStrings("", second.values[2]);
    try std.testing.expect((try parser.next()) == null);
}

test "parse_csv: preserves newlines in quoted values and returns first row" {
    const allocator = std.testing.allocator;
    var parser = CsvParser{
        .allocator = allocator,
        .input = "\"first line\nsecond line\",\"value\"\n\"next row\",\"value\"",
    };

    var first = (try parser.next()).?;
    defer first.deinit();
    try std.testing.expectEqualStrings("first line\nsecond line", first.values[0]);

    var second = (try parser.next()).?;
    defer second.deinit();
    try std.testing.expectEqualStrings("next row", second.values[0]);
    try std.testing.expect((try parser.next()) == null);
}

test "parse_csv: rejects malformed quoted values" {
    const allocator = std.testing.allocator;
    var unterminated = CsvParser{ .allocator = allocator, .input = "\"value" };
    try std.testing.expectError(CsvError.UnterminatedQuotedValue, unterminated.next());

    var trailing_text = CsvParser{ .allocator = allocator, .input = "\"value\"x" };
    try std.testing.expectError(CsvError.InvalidCharacterAfterQuote, trailing_text.next());

    var quote_in_bare_value = CsvParser{ .allocator = allocator, .input = "va\"lue" };
    try std.testing.expectError(CsvError.QuoteInUnquotedValue, quote_in_bare_value.next());
}
