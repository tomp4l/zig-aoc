const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const range = try parseInput(allocator, input);
    var part1_count: u32 = 0;
    var part2_count: u32 = 0;
    for (range.start..range.end + 1) |password| {
        const validity = validPassword(password);
        part1_count += @intFromBool(validity.non_strict);
        part2_count += @intFromBool(validity.strict);
    }
    try solution.part1(part1_count);
    try solution.part2(part2_count);
}

const Range = struct {
    start: u32,
    end: u32,
};

fn parseInput(allocator: Allocator, input: *std.Io.Reader) !Range {
    const line = try input.allocRemaining(allocator, .unlimited);
    defer allocator.free(line);
    var parts = std.mem.splitScalar(u8, line, '-');
    const start = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidInput, 10);
    const end = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidInput, 10);
    return Range{ .start = start, .end = end };
}

const Validity = struct {
    non_strict: bool,
    strict: bool,
};

fn validPassword(password: usize) Validity {
    var has_double = false;
    var has_exact_double = false;
    var double_count: usize = 0;

    var buf: [6]u8 = undefined;
    const string_repr = std.fmt.bufPrint(&buf, "{}", .{password}) catch @panic("expected 6 digit number");

    for (string_repr[0 .. string_repr.len - 1], string_repr[1..]) |c1, c2| {
        if (c2 < c1) {
            return Validity{ .non_strict = false, .strict = false };
        }
        if (c2 == c1) {
            has_double = true;
            double_count += 1;
        } else {
            has_exact_double = has_exact_double or double_count == 1;
            double_count = 0;
        }
    }
    return Validity{ .non_strict = has_double, .strict = has_exact_double or double_count == 1 };
}

test "parse input" {
    const allocator = std.testing.allocator;
    const input_data: []const u8 = "123456-654321";
    var input_reader = std.Io.Reader.fixed(input_data);
    const range = try parseInput(allocator, &input_reader);
    try std.testing.expect(range.start == 123456);
    try std.testing.expect(range.end == 654321);
}

test "valid passwords" {
    try std.testing.expect(validPassword(111111).non_strict == true);
    try std.testing.expect(validPassword(223450).non_strict == false);
    try std.testing.expect(validPassword(123789).non_strict == false);

    try std.testing.expect(validPassword(112233).strict == true);
    try std.testing.expect(validPassword(123444).strict == false);
    try std.testing.expect(validPassword(111122).strict == true);
}
