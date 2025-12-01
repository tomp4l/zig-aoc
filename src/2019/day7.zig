const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");
const Intcode = @import("Intcode.zig");

const util = @import("../util.zig");
const permutations = util.permutationIterator;

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);
    const part1 = try runAllAmplifierSettings(allocator, program);
    try solution.part1(part1);

    const part2 = try runAllAmplifierSettingsFeedbackLoop(allocator, program);
    try solution.part2(part2);
}

fn runAmplifiers(allocator: Allocator, program: []const Intcode.int_t, phase_settings: []const u8) !Intcode.int_t {
    var signal: Intcode.int_t = 0;

    for (phase_settings) |phase| {
        var amplifier = try Intcode.init(allocator, program);
        defer amplifier.deinit();

        _ = try amplifier.run();
        _ = try amplifier.provideInputAndRun(phase);
        _ = try amplifier.provideInputAndRun(signal);

        signal = amplifier.getLastOutput();
    }

    return signal;
}

fn runAll(allocator: Allocator, program: []const Intcode.int_t, settings: []const u8, runner: anytype) !Intcode.int_t {
    var max_signal: Intcode.int_t = 0;

    var perms = try permutations(5, settings);

    while (perms.next()) |phase_settings| {
        const signal = try runner(allocator, program, phase_settings);
        if (signal > max_signal) {
            max_signal = signal;
        }
    }

    return max_signal;
}

fn runAllAmplifierSettings(allocator: Allocator, program: []const Intcode.int_t) !Intcode.int_t {
    return runAll(allocator, program, &.{ 0, 1, 2, 3, 4 }, runAmplifiers);
}

fn runAmplifiersFeedbackLoop(allocator: Allocator, program: []const Intcode.int_t, phase_settings: []const u8) !Intcode.int_t {
    var amplifiers: [5]Intcode = undefined;

    var initialized: usize = 0;
    for (phase_settings, 0..) |phase, i| {
        amplifiers[i] = try Intcode.init(allocator, program);
        initialized += 1;
        _ = try amplifiers[i].run();
        _ = try amplifiers[i].provideInputAndRun(phase);
    }
    defer for (amplifiers[0..initialized]) |*amplifier| {
        amplifier.deinit();
    };

    var last_output: Intcode.int_t = 0;
    var halted = false;
    while (!halted) {
        for (&amplifiers) |*amplifier| {
            halted = try amplifier.provideInputAndRun(last_output);
            last_output = amplifier.getLastOutput();
        }
    }

    return last_output;
}

fn runAllAmplifierSettingsFeedbackLoop(allocator: Allocator, program: []const Intcode.int_t) !Intcode.int_t {
    return runAll(allocator, program, &.{ 5, 6, 7, 8, 9 }, runAmplifiersFeedbackLoop);
}

test "example p1" {
    const example_input: []const u8 =
        \\3,15,3,16,1002,16,10,16,1,16,15,15,4,15,99,0,0
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "43210",
        null,
    );
}

test "example p2" {
    const example_input: []const u8 =
        \\3,26,1001,26,-4,26,3,27,1002,27,2,27,1,27,26,27,4,27,1001,28,-1,28,1005,28,6,99,0,0,5
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "0",
        "139629729",
    );
}
