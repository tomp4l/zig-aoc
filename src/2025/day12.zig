const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const tree = try Tree.parse(allocator, input);
    defer tree.deinit(allocator);

    var possible_count: usize = 0;
    for (tree.areas) |area| {
        if (area.isDefinitelyPossible()) {
            possible_count += 1;
            continue;
        }
        if (!area.isImpossible(&tree.shapes) and !area.isDefinitelyPossible()) {
            return error.TooHard;
        }
    }

    try solution.part1(possible_count);
}

const Present = struct {
    id: usize,
    shape: [3][3]bool,

    fn parse(input: *std.Io.Reader) !@This() {
        const id_line = try input.takeDelimiter('\n') orelse return error.InvalidInput;
        const id = try std.fmt.parseInt(usize, id_line[0..1], 10);

        var shape: [3][3]bool = undefined;

        for (0..3) |y| {
            const line = try input.takeDelimiter('\n') orelse return error.InvalidInput;
            if (line.len < 3) {
                return error.InvalidInput;
            }

            for (0..3) |x| {
                shape[y][x] = switch (line[x]) {
                    '#' => true,
                    '.' => false,
                    else => return error.InvalidInput,
                };
            }
        }

        return .{
            .id = id,
            .shape = shape,
        };
    }
};

const Area = struct {
    width: usize,
    height: usize,
    presents: [6]usize,

    fn parse(line: []const u8) !@This() {
        var self = @This(){
            .width = 0,
            .height = 0,
            .presents = undefined,
        };
        var split = std.mem.tokenizeAny(u8, line, "x: ");
        const width_str = split.next() orelse return error.InvalidArea;
        self.width = try std.fmt.parseInt(usize, width_str, 10);
        const height_str = split.next() orelse return error.InvalidArea;
        self.height = try std.fmt.parseInt(usize, height_str, 10);
        for (&self.presents) |*present| {
            const part = split.next() orelse return error.InvalidArea;
            present.* = try std.fmt.parseInt(usize, part, 10);
        }

        return self;
    }

    fn isImpossible(self: *const @This(), presents: *const [6]Present) bool {
        var total_present_area: usize = 0;
        for (presents, self.presents) |present, amount| {
            var area: usize = 0;
            for (present.shape) |row| {
                for (row) |cell| {
                    if (cell) area += 1;
                }
            }
            total_present_area += area * amount;
        }

        return total_present_area > (self.width * self.height);
    }

    fn isDefinitelyPossible(self: *const @This()) bool {
        var total_present_area: usize = 0;
        for (self.presents) |amount| {
            total_present_area += 9 * amount;
        }

        return total_present_area <= self.width * self.height;
    }
};

const Tree = struct {
    shapes: [6]Present,
    areas: []Area,

    fn parse(allocator: Allocator, input: *std.Io.Reader) !@This() {
        var self = Tree{
            .shapes = undefined,
            .areas = undefined,
        };

        for (&self.shapes) |*shape| {
            shape.* = try Present.parse(input);
            _ = try input.discardDelimiterInclusive('\n');
        }

        self.areas = try parsing.parseAny(allocator, Area.parse, input, '\n');
        return self;
    }

    fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.areas);
    }
};

test "example" {
    const example_input: []const u8 =
        \\0:
        \\###
        \\##.
        \\##.
        \\
        \\1:
        \\###
        \\##.
        \\.##
        \\
        \\2:
        \\.##
        \\###
        \\##.
        \\
        \\3:
        \\##.
        \\###
        \\##.
        \\
        \\4:
        \\###
        \\#..
        \\###
        \\
        \\5:
        \\###
        \\.#.
        \\###
        \\ 
        \\4x4: 0 0 0 0 2 0
        \\12x5: 1 0 1 0 2 2
        \\12x5: 1 0 1 0 3 2
    ;

    const result = testing.assertSolutionOutput(
        run,
        example_input,
        "2",
        null,
    );

    try std.testing.expectError(error.TooHard, result);
}
