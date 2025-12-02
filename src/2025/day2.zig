const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const ranges = try parsing.parseAny(allocator, Range.parse, input, ',');
    defer allocator.free(ranges);
    const result = sumInvalidIds(ranges);
    try solution.part1(result.invalid_two_reps);
    try solution.part2(result.invalid_any_reps);
}

const Range = struct {
    start: usize,
    end: usize,

    fn parse(input: []const u8) !Range {
        var parts = std.mem.splitScalar(u8, input, '-');

        const start = try std.fmt.parseInt(usize, parts.next() orelse return error.InvalidRangeFormat, 10);
        const end = try std.fmt.parseInt(usize, parts.next() orelse return error.InvalidRangeFormat, 10);
        return Range{
            .start = start,
            .end = end,
        };
    }

    const RangeIterator = struct {
        current: usize,
        end: usize,

        pub fn next(self: *RangeIterator) ?usize {
            if (self.current > self.end) {
                return null;
            }
            const value = self.current;
            self.current += 1;
            return value;
        }
    };

    fn iter(self: Range) RangeIterator {
        return RangeIterator{
            .current = self.start,
            .end = self.end,
        };
    }
};

fn hasExactRepetitions(password_str: []const u8, repetitions: usize) bool {
    const password_len = password_str.len;
    if (password_len % repetitions != 0) {
        return false;
    }

    const split_len = password_len / repetitions;
    for (0..split_len) |i| {
        for (1..repetitions) |j| {
            if (password_str[i] != password_str[i + j * split_len]) {
                return false;
            }
        }
    }
    return true;
}

fn hasThreeOrMoreRepetitions(password_str: []const u8) bool {
    const max_repetitions_exclusive = password_str.len + 1;
    if (max_repetitions_exclusive <= 3) {
        return false;
    }
    for (3..max_repetitions_exclusive) |repetitions| {
        if (hasExactRepetitions(password_str, repetitions)) {
            return true;
        }
    }
    return false;
}

const Result = struct {
    invalid_two_reps: usize = 0,
    invalid_any_reps: usize = 0,
};

const RangeIntType = @FieldType(Range, "start");
const BUFFER_SIZE: usize = std.math.log10_int(@as(usize, @intCast(std.math.maxInt(RangeIntType)))) + 1;
fn sumInvalidIdsInRange(range: Range) Result {
    var result: Result = .{};
    var it = range.iter();
    while (it.next()) |password| {
        var password_buffer: [BUFFER_SIZE]u8 = undefined;
        const password_str = std.fmt.bufPrint(&password_buffer, "{}", .{password}) catch unreachable;
        if (hasExactRepetitions(password_str, 2)) {
            result.invalid_two_reps += password;
            result.invalid_any_reps += password;
        } else if (hasThreeOrMoreRepetitions(password_str)) {
            result.invalid_any_reps += password;
        }
    }
    return result;
}

fn sumInvalidIds(ranges: []const Range) Result {
    var total: Result = .{};
    for (ranges) |range| {
        const result = sumInvalidIdsInRange(range);
        total.invalid_two_reps += result.invalid_two_reps;
        total.invalid_any_reps += result.invalid_any_reps;
    }
    return total;
}

test "example" {
    const example_input: []const u8 =
        \\11-22,95-115,998-1012,1188511880-1188511890,222220-222224,1698522-1698528,446443-446449,38593856-38593862,565653-565659,824824821-824824827,2121212118-2121212124
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "1227775554",
        "4174379265",
    );
}
