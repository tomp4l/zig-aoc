const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var manifold = try TachyonManifold.parse(allocator, input);
    defer manifold.deinit();

    const result = try manifold.countSplits(allocator);
    try solution.part1(result.splits);
    try solution.part2(result.paths);
}

const Coord = struct {
    x: i32,
    y: i32,
};
const TachyonManifold = struct {
    start: Coord,
    splitters: std.AutoHashMap(Coord, void),
    end: i32,

    fn parse(allocator: Allocator, input: *std.Io.Reader) !TachyonManifold {
        var splitters = std.AutoHashMap(Coord, void).init(allocator);
        errdefer splitters.deinit();
        var start: ?Coord = undefined;
        var row: i32 = 0;
        while (try input.takeDelimiter('\n')) |line| {
            for (line, 0..) |char, col| {
                switch (char) {
                    'S' => start = .{ .x = @intCast(col), .y = row },
                    '^' => try splitters.put(.{ .x = @intCast(col), .y = row }, {}),
                    '.' => {},
                    else => return error.InvalidCharacter,
                }
            }
            row += 1;
        }
        return .{
            .start = start orelse return error.MissingStartPosition,
            .splitters = splitters,
            .end = row,
        };
    }

    const Result = struct {
        splits: usize,
        paths: usize,
    };

    const CoordNode = struct {
        coord: Coord,
        node: std.DoublyLinkedList.Node,
    };

    fn putCoord(allocator: Allocator, visited: *std.AutoHashMap(Coord, usize), beams: *std.DoublyLinkedList, coord: Coord, count: usize) !void {
        if (visited.getPtr(coord)) |v| {
            v.* += count;
        } else {
            try visited.put(coord, count);
            const coord_node = try allocator.create(CoordNode);
            coord_node.* = .{ .coord = coord, .node = .{} };
            beams.append(&coord_node.node);
        }
    }

    fn countSplits(self: *TachyonManifold, allocator: Allocator) !Result {
        var visited = std.AutoHashMap(Coord, usize).init(allocator);
        defer visited.deinit();

        var beams = std.DoublyLinkedList{};
        const start_node = try allocator.create(CoordNode);
        start_node.* = .{ .coord = self.start, .node = .{} };
        beams.append(&start_node.node);
        try visited.put(self.start, 1);
        defer {
            while (beams.pop()) |node| {
                const coord_node: *CoordNode = @fieldParentPtr("node", node);
                allocator.destroy(coord_node);
            }
        }

        var splits: usize = 0;
        var paths: usize = 0;
        while (beams.popFirst()) |node| {
            const coord_node: *CoordNode = @fieldParentPtr("node", node);
            defer allocator.destroy(coord_node);
            const coord = coord_node.coord;
            const count = visited.get(coord).?;

            if (coord.y == self.end) {
                paths += count;
                continue;
            }

            const below = Coord{ .x = coord.x, .y = coord.y + 1 };
            if (self.splitters.contains(below)) {
                const left = Coord{ .x = coord.x - 1, .y = coord.y + 1 };
                const right = Coord{ .x = coord.x + 1, .y = coord.y + 1 };

                try putCoord(allocator, &visited, &beams, left, count);
                try putCoord(allocator, &visited, &beams, right, count);

                splits += 1;
            } else {
                try putCoord(allocator, &visited, &beams, below, count);
            }
        }

        return .{
            .splits = splits,
            .paths = paths,
        };
    }

    fn deinit(self: *TachyonManifold) void {
        self.splitters.deinit();
    }
};

test "example" {
    const example_input: []const u8 =
        \\.......S.......
        \\...............
        \\.......^.......
        \\...............
        \\......^.^......
        \\...............
        \\.....^.^.^.....
        \\...............
        \\....^.^...^....
        \\...............
        \\...^.^...^.^...
        \\...............
        \\..^...^.....^..
        \\...............
        \\.^.^.^.^.^...^.
        \\...............
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "21",
        "40",
    );
}
