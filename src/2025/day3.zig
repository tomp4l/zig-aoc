const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const banks = try parsing.parseAny(allocator, BatteryBank.parse, input, '\n');
    defer {
        for (banks) |bank| {
            bank.deinit(allocator);
        }
        allocator.free(banks);
    }
    var total_joltage: u64 = 0;
    var total_joltage_override: u64 = 0;

    for (banks) |bank| {
        total_joltage += bank.maxPower(2);
        total_joltage_override += bank.maxPower(12);
    }

    try solution.part1(total_joltage);
    try solution.part2(total_joltage_override);
}

const BatteryBank = struct {
    batteries: []u8,

    fn deinit(self: BatteryBank, allocator: Allocator) void {
        allocator.free(self.batteries);
    }

    fn parse(allocator: Allocator, line: []const u8) !BatteryBank {
        var batteries = try allocator.alloc(u8, line.len);
        for (line, 0..) |char, idx| {
            batteries[idx] = char - '0';
        }
        return BatteryBank{
            .batteries = batteries,
        };
    }

    fn maxPower(self: BatteryBank, length: comptime_int) u64 {
        std.debug.assert(length <= self.batteries.len);
        comptime std.debug.assert(length <= 19);

        var remaining_needed: usize = length;
        var start: usize = 0;
        var result: u64 = 0;

        while (remaining_needed > 0) : (remaining_needed -= 1) {
            const remaining_available = self.batteries.len - start;
            const search_end = start + remaining_available - remaining_needed + 1;

            const max_in_range = std.mem.findMax(u8, self.batteries[start..search_end]);
            start += max_in_range + 1;
            result = result * 10 + self.batteries[start - 1];
        }

        return result;
    }
};

test "example" {
    const example_input: []const u8 =
        \\987654321111111
        \\811111111111119
        \\234234234234278
        \\818181911112111
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "357",
        "3121910778619",
    );
}
