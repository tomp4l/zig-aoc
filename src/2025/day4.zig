const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var department = try PrintingDepartment.parse(allocator, input);
    defer department.deinit();

    try solution.part1(department.accessibleRolls());
    const initial_count = department.paper.count();
    try department.removeAllAccessible(allocator);
    const end_count = department.paper.count();
    try solution.part2(initial_count - end_count);
}

const Coord = struct {
    x: i32,
    y: i32,
};

const PrintingDepartment = struct {
    paper: std.AutoHashMap(Coord, void),
    width: u32 = 0,
    height: u32 = 0,

    pub fn parse(allocator: Allocator, reader: *std.Io.Reader) !PrintingDepartment {
        var department = PrintingDepartment{
            .paper = std.AutoHashMap(Coord, void).init(allocator),
        };

        var row: u32 = 0;
        var col: u32 = 0;
        while (true) {
            var line_writer = std.Io.Writer.Allocating.init(allocator);
            defer line_writer.deinit();
            const line_length = try reader.streamDelimiterEnding(&line_writer.writer, '\n');
            if (line_length == 0) break;

            for (line_writer.written()) |c| {
                if (c == '@') {
                    try department.paper.put(.{ .x = @intCast(col), .y = @intCast(row) }, {});
                }
                col += 1;
            }
            department.width = col;
            row += 1;
            col = 0;
            reader.discardAll(1) catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
        }
        department.height = row;

        return department;
    }

    fn accessibleRolls(self: *const @This()) usize {
        var roll_it = self.paper.keyIterator();
        var accessible_count: usize = 0;
        while (roll_it.next()) |coord| {
            if (self.isAccessible(coord)) {
                accessible_count += 1;
            }
        }
        return accessible_count;
    }

    const OFFSETS = [_]Coord{
        .{ .x = 0, .y = -1 },
        .{ .x = 0, .y = 1 },
        .{ .x = -1, .y = 0 },
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = -1 },
        .{ .x = 1, .y = -1 },
        .{ .x = -1, .y = 1 },
        .{ .x = 1, .y = 1 },
    };
    const MAX_NEIGHBOURS: usize = 4;
    fn isAccessible(self: *const @This(), coord: *const Coord) bool {
        var neighbour_count: usize = 0;
        inline for (OFFSETS) |offset| {
            const neighbour = Coord{ .x = coord.x + offset.x, .y = coord.y + offset.y };
            if (self.paper.contains(neighbour)) {
                neighbour_count += 1;
                if (neighbour_count >= MAX_NEIGHBOURS) {
                    return false;
                }
            }
        }
        return true;
    }

    fn removeAccessible(self: *@This(), allocator: Allocator) !void {
        var roll_it = self.paper.keyIterator();
        var to_remove = try std.ArrayList(Coord).initCapacity(allocator, 1024);
        defer to_remove.deinit(allocator);

        while (roll_it.next()) |coord| {
            if (self.isAccessible(coord)) {
                try to_remove.append(allocator, coord.*);
            }
        }

        for (to_remove.items) |coord| {
            _ = self.paper.remove(coord);
        }
    }

    fn removeAllAccessible(self: *@This(), allocator: Allocator) !void {
        while (true) {
            const initial_count = self.paper.count();
            try self.removeAccessible(allocator);
            if (self.paper.count() == initial_count) {
                break;
            }
        }
    }

    fn deinit(self: *@This()) void {
        self.paper.deinit();
    }
};

test "example" {
    const example_input: []const u8 =
        \\..@@.@@@@.
        \\@@@.@.@.@@
        \\@@@@@.@.@@
        \\@.@@@@..@.
        \\@@.@@@@.@@
        \\.@@@@@@@.@
        \\.@.@.@.@@@
        \\@.@@@.@@@@
        \\.@@@@@@@@.
        \\@.@.@@@.@.
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "13",
        "43",
    );
}
