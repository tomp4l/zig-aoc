const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");
const assertSolutionOutput = testing.assertSolutionOutput;

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const masses = try parsing.parseIntLines(u32, allocator, input);
    defer allocator.free(masses);
    var total_fuel: u32 = 0;
    var total_fuel_recursive: u32 = 0;
    for (masses) |mass| {
        total_fuel += fuel(mass);
        total_fuel_recursive += fuelRecursive(mass);
    }
    try solution.part1(total_fuel);
    try solution.part2(total_fuel_recursive);
}

fn fuel(mass: u32) u32 {
    if (mass < 2 * 3) {
        return 0;
    }
    return @divTrunc(mass, 3) - 2;
}

fn fuelRecursive(mass: u32) u32 {
    var remaining = mass;
    var total: u32 = 0;
    while (remaining > 0) {
        remaining = fuel(remaining);
        total += remaining;
    }
    return total;
}

test "expected fuel" {
    try std.testing.expect(fuel(12) == 2);
    try std.testing.expect(fuel(14) == 2);
    try std.testing.expect(fuel(1969) == 654);
    try std.testing.expect(fuel(100756) == 33583);
}

test "expected fuel recursive" {
    try std.testing.expect(fuelRecursive(12) == 2);
    try std.testing.expect(fuelRecursive(14) == 2);
    try std.testing.expect(fuelRecursive(1969) == 966);
    try std.testing.expect(fuelRecursive(100756) == 50346);
}

test "parts" {
    const input_data: []const u8 =
        \\12
        \\14
        \\1969
        \\100756
    ;
    try assertSolutionOutput(
        run,
        input_data,
        "34241",
        "51316",
    );
}
