const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

width: usize = 25,
height: usize = 6,

pub fn run(comptime self: @This(), allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    _ = allocator;

    const layer_size = self.width * self.height;
    var current_buffer: [layer_size]u8 = undefined;
    var image: [layer_size]u8 = @splat('2');

    var min_zero_count: usize = layer_size + 1;
    var part1_result: usize = 0;

    while (input.peekByte() catch null) |_| {
        try input.readSliceAll(&current_buffer);
        var zero_count: usize = 0;
        var one_count: usize = 0;
        var two_count: usize = 0;
        for (current_buffer) |pixel| {
            switch (pixel) {
                '0' => zero_count += 1,
                '1' => one_count += 1,
                '2' => two_count += 1,
                else => {},
            }
        }

        if (zero_count < min_zero_count) {
            min_zero_count = zero_count;
            part1_result = one_count * two_count;
        }

        for (current_buffer, &image) |pixel, *dest_pixel| {
            if ((dest_pixel.* == '2') and (pixel != '2')) {
                dest_pixel.* = pixel;
            }
        }
    }

    try solution.part1(part1_result);

    var output: [self.height * self.width + self.height + 1]u8 = undefined;

    output[0] = '\n';
    var output_index: usize = 1;
    for (0..self.height) |row| {
        for (0..self.width) |col| {
            const pixel = image[row * self.width + col];
            output[output_index] = switch (pixel) {
                '0' => ' ',
                '1' => '#',
                else => ' ',
            };
            output_index += 1;
        }
        output[output_index] = '\n';
        output_index += 1;
    }

    try solution.part2(output[0..output_index]);
}

test "example" {
    var reader = std.Io.Reader.fixed("0222112222120000");
    var solution: testing.TestSolution = undefined;
    solution.init();
    defer solution.deinit();
    const self: @This() = .{ .width = 2, .height = 2 };
    try self.run(std.heap.page_allocator, &reader, &solution.solution);

    const expected =
        \\Part 1: 4
        \\Part 2: 
        \\ #
        \\# 
        \\
        \\
    ;

    try std.testing.expectEqualStrings(expected, solution.writer.written());
}
