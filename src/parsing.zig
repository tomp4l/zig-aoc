const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn parseIntLines(T: type, allocator: Allocator, input: *std.Io.Reader) ![]T {
    return parseInt(T, allocator, input, '\n');
}

pub fn parseInt(T: type, allocator: Allocator, input: *std.Io.Reader, delimiter: u8) ![]T {
    const IntParser = struct {
        fn parse(line: []const u8) !T {
            return std.fmt.parseInt(T, line, 10);
        }
    };
    return parseAny(allocator, IntParser.parse, input, delimiter);
}

fn ParseReturnType(T: type) type {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .@"fn" => |f| {
            const ret = f.return_type orelse void;
            const ret_info = @typeInfo(ret);
            switch (ret_info) {
                .error_union => |eu| {
                    return eu.payload;
                },
                else => {
                    @compileError("invalid type, expected ([]const u8) => !T");
                },
            }
        },
        else => @compileError("invalid type, expected ([]const u8) => !T"),
    };
}

pub fn parseAny(allocator: Allocator, parser: anytype, input: *std.Io.Reader, delimiter: u8) ![]ParseReturnType(@TypeOf(parser)) {
    const T = ParseReturnType(@TypeOf(parser));
    const ParserType = @TypeOf(parser);
    const needs_alloc = switch (@typeInfo(ParserType)) {
        .@"fn" => |f| f.params.len == 2,
        else => return error.InvalidParserFunctionType,
    };

    var result = try std.ArrayList(T).initCapacity(allocator, 100);
    errdefer {
        if (needs_alloc) {
            for (result.items) |*item| {
                item.deinit(allocator);
            }
        }
        result.deinit(allocator);
    }

    while (true) {
        var line = std.Io.Writer.Allocating.init(allocator);
        defer line.deinit();
        _ = try input.streamDelimiterEnding(&line.writer, delimiter);
        const line_slice = line.written();
        if (line_slice.len == 0) break;
        const value = if (needs_alloc) try parser(allocator, line_slice) else try parser(line_slice);
        try result.append(allocator, value);
        input.discardAll(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
    }

    return result.toOwnedSlice(allocator);
}

test "parse any allocator cleanup" {
    const TestType = struct {
        value: []const u8,
        fn deinit(self: *@This(), allocator: Allocator) void {
            allocator.free(self.value);
        }

        fn parse(allocator: Allocator, line: []const u8) !@This() {
            if (std.mem.eql(u8, line, "error")) {
                return error.TestError;
            }
            const duped = try allocator.dupe(u8, line);
            return @This(){ .value = duped };
        }
    };
    const test_input =
        \\line1
        \\line2
        \\error
        \\line3
    ;

    const allocator = std.testing.allocator;
    var reader = std.Io.Reader.fixed(test_input);
    _ = parseAny(allocator, TestType.parse, &reader, '\n') catch |e| {
        try std.testing.expectEqual(error.TestError, e);
        return;
    };
    try std.testing.expect(false);
}
