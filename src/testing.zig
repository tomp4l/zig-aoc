const std = @import("std");
const root = @import("root.zig");
const testing = std.testing;

pub const TestSolution = struct {
    writer: std.Io.Writer.Allocating,
    solution: root.Solution,

    pub fn init(solution: *TestSolution) void {
        solution.writer = std.Io.Writer.Allocating.init(std.testing.allocator);
        solution.solution = root.Solution{
            .writer = &solution.writer.writer,
        };
    }

    pub fn deinit(self: *TestSolution) void {
        self.writer.deinit();
    }
};

pub fn assertSolutionOutput(
    solution_fn: anytype,
    input_data: []const u8,
    expected_part1: []const u8,
    maybe_expected_part2: ?[]const u8,
) !void {
    const allocator = std.testing.allocator;
    var output_buffer = std.Io.Writer.Allocating.init(allocator);

    var solution = root.Solution{
        .writer = &output_buffer.writer,
    };

    var input_reader = std.Io.Reader.fixed(input_data);

    switch (@typeInfo(@TypeOf(solution_fn))) {
        .@"fn" => try solution_fn(allocator, &input_reader, &solution),
        .@"struct" => try solution_fn.run(allocator, &input_reader, &solution),
        else => return error.InvalidSolutionFunctionType,
    }

    const output_slice = try output_buffer.toOwnedSlice();
    defer allocator.free(output_slice);

    var lines = std.mem.splitAny(u8, output_slice, "\n");
    const part1_line = lines.next() orelse
        return error.MissingOutputPart1;

    try testing.expectEqualStrings(expected_part1, part1_line[8..]);

    if (maybe_expected_part2) |expected_part2| {
        const part2_line = lines.next() orelse
            return error.MissingOutputPart2;
        try testing.expectEqualStrings(expected_part2, part2_line[8..]);
    }
}

pub fn assertSolution(
    solution_fn: anytype,
    input_data: []const u8,
    expected_output: []const u8,
) !void {
    const allocator = std.testing.allocator;
    var output_buffer = std.Io.Writer.Allocating.init(allocator);
    defer output_buffer.deinit();

    var solution = root.Solution{
        .writer = &output_buffer.writer,
    };

    var input_reader = std.Io.Reader.fixed(input_data);

    switch (@typeInfo(@TypeOf(solution_fn))) {
        .@"fn" => try solution_fn(allocator, &input_reader, &solution),
        .@"struct" => try solution_fn.run(allocator, &input_reader, &solution),
        else => return error.InvalidSolutionFunctionType,
    }

    try std.testing.expectEqualStrings(expected_output, output_buffer.written());
}
