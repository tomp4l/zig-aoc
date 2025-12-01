const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    _ = allocator;
    _ = input;
    _ = solution;
}

test "example" {
    if (true) return error.SkipZigTest;

    const example_input: []const u8 =
        \\
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "",
        null,
    );
}
