const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

const FFT_PHASES = 100;
const FFT_REPETITIONS = 10000;

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const input_digits = try parseInput(allocator, input);
    defer allocator.free(input_digits);

    const part1_result = try fft(allocator, input_digits, FFT_PHASES);
    defer allocator.free(part1_result);
    var output: [8]u8 = undefined;
    for (0..8) |i| {
        output[i] = part1_result[i] + '0';
    }
    try solution.part1(&output);

    var part2_offset: usize = 0;
    for (0..7) |i| {
        part2_offset = part2_offset * 10 + @as(usize, input_digits[i]);
    }

    const part2_result = try flawedEightDigitsAt(allocator, input_digits, FFT_REPETITIONS, part2_offset, FFT_PHASES);

    var part2_output: [8]u8 = undefined;
    for (0..8) |i| {
        part2_output[i] = part2_result[i] + '0';
    }
    try solution.part2(&part2_output);
}

fn allocateSuffix(allocator: Allocator, input_unrepeated: []const u8, repetitions: usize, offset: usize) ![]u8 {
    const input_len = input_unrepeated.len * repetitions;
    const suffix_len = input_len - offset;
    const mod_offset = suffix_len % input_unrepeated.len;
    const suffix = try allocator.alloc(u8, suffix_len);

    @memcpy(suffix[0..mod_offset], input_unrepeated[input_unrepeated.len - mod_offset .. input_unrepeated.len]);
    const remaining_repetitions = suffix_len / input_unrepeated.len;
    for (0..remaining_repetitions) |i| {
        @memcpy(
            suffix[i * input_unrepeated.len + mod_offset .. (i + 1) * input_unrepeated.len + mod_offset],
            input_unrepeated,
        );
    }
    return suffix;
}

fn flawedEightDigitsAt(allocator: Allocator, input_unrepeated: []const u8, repetitions: usize, offset: usize, phases: usize) ![8]u8 {
    var suffix = try allocateSuffix(allocator, input_unrepeated, repetitions, offset);
    defer allocator.free(suffix);
    const suffix_len = suffix.len;

    std.debug.assert(8 <= suffix.len);
    std.debug.assert(suffix.len < repetitions * input_unrepeated.len / 2);

    for (0..phases) |_| {
        var sum: u8 = 0;
        for (0..suffix_len) |i| {
            sum += suffix[suffix_len - 1 - i];
            if (sum >= 10) {
                sum -= 10;
            }
            suffix[suffix_len - 1 - i] = sum;
        }
    }

    var output: [8]u8 = undefined;
    for (0..8) |i| {
        output[i] = suffix[i];
    }
    return output;
}

fn parseInput(allocator: Allocator, input: *std.Io.Reader) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    while (input.takeByte() catch |e| switch (e) {
        error.EndOfStream => null,
        else => return e,
    }) |b| {
        if (b >= '0' and b <= '9') {
            try buffer.append(allocator, b - '0');
        } else {
            return error.InvalidInputCharacter;
        }
    }
    return buffer.toOwnedSlice(allocator);
}

fn fft_phase(input: []const u8, output: []u8) !void {
    const length = input.len;
    std.debug.assert(output.len == length);

    for (0..length) |i| {
        var sum: i32 = 0;
        const repeat = i + 1;

        var pos = repeat - 1;

        while (pos < length) : (pos += repeat * 4) {
            const end = @min(pos + repeat, length);
            for (pos..end) |j| {
                sum += input[j];
            }
        }

        pos = repeat * 3 - 1;
        while (pos < length) : (pos += repeat * 4) {
            const end = @min(pos + repeat, length);
            for (pos..end) |j| {
                sum -= input[j];
            }
        }

        output[i] = @intCast(@abs(sum) % 10);
    }
}

fn fft(allocator: Allocator, input: []const u8, phases: usize) ![]u8 {
    var current = try allocator.alloc(u8, input.len);
    @memcpy(current, input);

    var next = try allocator.alloc(u8, input.len);
    defer allocator.free(next);

    for (0..phases) |phase| {
        _ = phase;
        try fft_phase(current, next);
        const temp = current;
        current = next;
        next = temp;
    }

    return current;
}

test "single phase 1" {
    const input: [8]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var output: [8]u8 = undefined;

    try fft_phase(&input, &output);

    const expected: [8]u8 = .{ 4, 8, 2, 2, 6, 1, 5, 8 };
    try std.testing.expectEqualSlices(u8, &expected, &output);
}

test "example" {
    const example_input: []const u8 =
        \\80871224585914546619083218645595
    ;

    const expected_output: [8]u8 = .{ 2, 4, 1, 7, 6, 1, 7, 6 };
    const allocator = std.testing.allocator;
    var reader = std.Io.Reader.fixed(example_input);
    const input_digits = try parseInput(allocator, &reader);
    defer allocator.free(input_digits);
    const output = try fft(allocator, input_digits, 100);
    defer allocator.free(output);

    try std.testing.expectEqualSlices(u8, &expected_output, output[0..8]);
}

test "flawed example" {
    const example_input: []const u8 =
        \\03036732577212944063491565474664
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "24465799",
        "84462026",
    );
}
