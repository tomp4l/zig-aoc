const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn parseIntLines(T: type, allocator: Allocator, input: *std.Io.Reader) ![]T {
    return parseInt(T, allocator, input, '\n');
}

pub fn parseInt(T: type, allocator: Allocator, input: *std.Io.Reader, delimiter: u8) ![]T {
    var result = try std.ArrayList(T).initCapacity(allocator, 100);
    errdefer result.deinit(allocator);
    while (true) {
        var line = std.Io.Writer.Allocating.init(allocator);
        _ = try input.streamDelimiterEnding(&line.writer, delimiter);
        const line_slice = try line.toOwnedSlice();
        defer allocator.free(line_slice);

        if (line_slice.len == 0) break;
        const value = try std.fmt.parseInt(T, line_slice, 10);
        try result.append(allocator, value);
        input.discardAll(1) catch break;
    }

    return result.toOwnedSlice(allocator);
}
