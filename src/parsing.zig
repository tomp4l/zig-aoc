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
    var result = try std.ArrayList(T).initCapacity(allocator, 100);
    errdefer result.deinit(allocator);
    while (true) {
        var line = std.Io.Writer.Allocating.init(allocator);
        _ = try input.streamDelimiterEnding(&line.writer, delimiter);
        const line_slice = try line.toOwnedSlice();
        defer allocator.free(line_slice);

        if (line_slice.len == 0) break;
        const value = try parser(line_slice);
        try result.append(allocator, value);
        input.discardAll(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
    }

    return result.toOwnedSlice(allocator);
}
