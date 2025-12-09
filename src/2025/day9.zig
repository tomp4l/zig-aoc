const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const coords = try parsing.parseAny(allocator, Coord.parse, input, '\n');
    defer allocator.free(coords);
    const area = biggestRectangle(coords);
    try solution.part1(area);
    const contained_area = try biggestContainedRectangle(allocator, coords);
    try solution.part2(contained_area);
}

fn biggestRectangle(coords: []const Coord) u64 {
    var biggest: u64 = 0;

    for (coords, 0..) |a, i| {
        for (coords[i + 1 ..]) |b| {
            const width = if (a.x > b.x) a.x - b.x else b.x - a.x;
            const height = if (a.y > b.y) a.y - b.y else b.y - a.y;
            const area = (width + 1) * (height + 1);
            if (area > biggest) {
                biggest = area;
            }
        }
    }
    return biggest;
}

const Segment = struct {
    start: *const Coord,
    end: *const Coord,

    fn isHorizontal(self: Segment) bool {
        return self.start.y == self.end.y;
    }

    fn intersects(self: Segment, other: Segment) bool {
        const self_is_horiz = self.isHorizontal();
        const other_is_horiz = other.isHorizontal();

        if (self_is_horiz == other_is_horiz) return false;

        const horiz = if (self_is_horiz) self else other;
        const vert = if (self_is_horiz) other else self;

        const horiz_min_x = @min(horiz.start.x, horiz.end.x);
        const horiz_max_x = @max(horiz.start.x, horiz.end.x);
        const vert_min_y = @min(vert.start.y, vert.end.y);
        const vert_max_y = @max(vert.start.y, vert.end.y);

        if (vert.start.x > horiz_min_x and vert.start.x < horiz_max_x and
            horiz.start.y > vert_min_y and horiz.start.y < vert_max_y)
        {
            return true;
        }
        return false;
    }
};

fn buildSegments(allocator: Allocator, coords: []const Coord) ![]Segment {
    const first = &coords[0];
    var current = first;
    var segments = try std.ArrayList(Segment).initCapacity(allocator, coords.len);

    for (coords[1..]) |*coord| {
        segments.appendAssumeCapacity(.{ .start = current, .end = coord });
        current = coord;
    }

    segments.appendAssumeCapacity(.{ .start = current, .end = first });
    return try segments.toOwnedSlice(allocator);
}

fn biggestContainedRectangle(allocator: Allocator, coords: []const Coord) !u64 {
    var biggest: u64 = 0;
    const segments = try buildSegments(allocator, coords);
    defer allocator.free(segments);
    for (coords, 0..) |a, i| {
        for (coords[i + 1 ..]) |b| {
            const width = if (a.x > b.x) a.x - b.x else b.x - a.x;
            const height = if (a.y > b.y) a.y - b.y else b.y - a.y;
            const area = (width + 1) * (height + 1);
            if (area <= biggest) continue;
            // Assumes it won't be this small as below check won't work
            // Real input uses big numbers
            if (width < 2 or height < 2) continue;

            const min_x = @min(a.x, b.x);
            const max_x = @max(a.x, b.x);
            const min_y = @min(a.y, b.y);
            const max_y = @max(a.y, b.y);

            const inside_points = [4]Coord{
                .{ .x = min_x + 1, .y = min_y + 1 },
                .{ .x = min_x + 1, .y = max_y - 1 },
                .{ .x = max_x - 1, .y = min_y + 1 },
                .{ .x = max_x - 1, .y = max_y - 1 },
            };

            var is_outside = false;
            inline for (inside_points) |point| {
                var crossings: usize = 0;
                for (segments) |seg| {
                    if (seg.start.x == seg.end.x) continue;
                    if (seg.start.y < point.y) continue;
                    const seg_min_x = @min(seg.start.x, seg.end.x);
                    const seg_max_x = @max(seg.start.x, seg.end.x);
                    if (point.x < seg_min_x or point.x > seg_max_x) continue;
                    crossings += 1;
                }
                is_outside = (crossings % 2) == 0;
                if (is_outside) break;
            }
            if (is_outside) continue;

            const inner_edges = [4]Segment{
                .{ .start = &Coord{ .x = min_x + 1, .y = min_y }, .end = &Coord{ .x = min_x + 1, .y = max_y } },
                .{ .start = &Coord{ .x = min_x, .y = max_y - 1 }, .end = &Coord{ .x = max_x, .y = max_y - 1 } },
                .{ .start = &Coord{ .x = max_x - 1, .y = max_y }, .end = &Coord{ .x = max_x - 1, .y = min_y } },
                .{ .start = &Coord{ .x = max_x, .y = min_y + 1 }, .end = &Coord{ .x = min_x, .y = min_y + 1 } },
            };

            var intersects = false;
            inline for (inner_edges) |edge| {
                for (segments) |seg| {
                    intersects = seg.intersects(edge);
                    if (intersects) break;
                }
                if (intersects) break;
            }

            if (intersects) continue;
            biggest = area;
        }
    }
    return biggest;
}

const Coord = struct {
    x: u64,
    y: u64,

    fn parse(line: []const u8) !Coord {
        var parts = std.mem.splitScalar(u8, line, ',');
        const x_str = parts.next() orelse return error.InvalidCoordinate;
        const y_str = parts.next() orelse return error.InvalidCoordinate;

        const x = try std.fmt.parseInt(u64, x_str, 10);
        const y = try std.fmt.parseInt(u64, y_str, 10);

        return Coord{ .x = x, .y = y };
    }
};

test "example" {
    const example_input: []const u8 =
        \\7,1
        \\11,1
        \\11,7
        \\9,7
        \\9,5
        \\2,5
        \\2,3
        \\7,3
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "50",
        "24",
    );
}

test "example with convex shape" {
    //    1 2 3 4 5 6 7 8
    //
    // 1  # O O O X X X #
    // 2  O O O O X X X X
    // 3  O O O O X X X X
    // 4  O O O # X # X X
    // 5  O O O O   X X X
    // 6  O O O O   X X X
    // 7  O O O O   X X X
    // 8  # O O #   # X #
    const example_input: []const u8 =
        \\1,1
        \\8,1
        \\8,8
        \\6,8
        \\6,4
        \\4,4
        \\4,8
        \\1,8
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "64", // 8 x 8
        "32", // 8 x 4
    );
}

test "example with L shape" {
    //    1 2 3 4 5 6
    //
    // 1  # O O O X #
    // 2  O O O O X X
    // 3  O O O O X X
    // 4  O O O # X #
    // 5  O O O O
    // 6  O O O O
    // 7  O O O O
    // 8  # O O #
    const example_input: []const u8 =
        \\1,1
        \\6,1
        \\6,4
        \\4,4
        \\4,8
        \\1,8
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "48", // 6 x 8
        "32", // 8 x 4
    );
}
