const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");
const Intcode = @import("Intcode.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);

    try solution.part1(runWithInput(allocator, program, 1));
    try solution.part2(runWithInput(allocator, program, 2));
}

fn runWithInput(allocator: Allocator, program: []const Intcode.int_t, input_value: Intcode.int_t) !Intcode.int_t {
    var intcode = try Intcode.init(allocator, program);
    defer intcode.deinit();
    _ = try intcode.run();
    _ = try intcode.provideInputAndRun(input_value);
    return intcode.getLastOutput();
}
