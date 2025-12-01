const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");
const Intcode = @import("Intcode.zig");

target_output: Intcode.int_t = 19690720,

pub fn run(self: @This(), allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);
    var intcode = try Intcode.init(allocator, program);
    defer intcode.deinit();
    _ = try intcode.run();
    const part1_result = intcode.memoryAt(0);

    const part2_result = try searchNounAndVerb(allocator, program, self.target_output);
    try solution.part1(part1_result);
    try solution.part2(part2_result);
}

pub fn searchNounAndVerb(
    allocator: Allocator,
    original_program: []const Intcode.int_t,
    target_output: Intcode.int_t,
) !u32 {
    for (0..100) |noun| {
        for (0..100) |verb| {
            var intcode = try Intcode.init(allocator, original_program);
            defer intcode.deinit();
            try intcode.setMemory(1, @intCast(noun));
            try intcode.setMemory(2, @intCast(verb));
            _ = try intcode.run();
            const output = intcode.memoryAt(0);
            if (output == target_output) {
                return @intCast(noun * 100 + verb);
            }
        }
    }
    return error.NotFound;
}

test "example" {
    const example_input: []const u8 =
        \\1,9,10,3,2,3,11,0,99,30,40,50
    ;

    try testing.assertSolutionOutput(
        @This(){ .target_output = 3500 },
        example_input,
        "3500",
        "270",
    );
}
