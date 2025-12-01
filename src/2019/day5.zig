const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const Intcode = @import("./Intcode.zig");
const parsing = @import("../parsing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);

    const part1_result = try diagnosticCode(allocator, program, 1);
    const part2_result = try diagnosticCode(allocator, program, 5);
    try solution.part1(part1_result);
    try solution.part2(part2_result);
}

fn diagnosticCode(allocator: Allocator, program: []const Intcode.int_t, input_value: Intcode.int_t) !Intcode.int_t {
    var intcode = try Intcode.init(allocator, program);
    defer intcode.deinit();
    while (!try intcode.run()) {
        try intcode.provideInput(input_value);
    }
    return intcode.getLastOutput();
}
