const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const wires = try parse(allocator, input);
    defer wires.deinit(allocator);

    const results = try wires.closestCrossing(allocator);

    try solution.part1(results.closest_manhattan);
    try solution.part2(results.closest_path_length);
}

const Direction = enum {
    Up,
    Down,
    Left,
    Right,
};

const WireSegment = struct {
    direction: Direction,
    length: u32,
};

const Wires = struct {
    first: []WireSegment,
    second: []WireSegment,

    fn deinit(self: Wires, allocator: Allocator) void {
        allocator.free(self.first);
        allocator.free(self.second);
    }

    const Crossings = struct {
        closest_manhattan: u32,
        closest_path_length: u32,
    };

    fn compareAndSetClosest(current: anytype, candidate: anytype) void {
        if (current.*) |cur| {
            if (candidate < cur) {
                current.* = candidate;
            }
        } else {
            current.* = candidate;
        }
    }

    fn closestCrossing(self: Wires, allocator: Allocator) !Crossings {
        const first_segments = try buildSegments(allocator, self.first);
        defer allocator.free(first_segments);

        const second_segments = try buildSegments(allocator, self.second);
        defer allocator.free(second_segments);

        var closest_manhattan: ?u32 = null;
        var closest_path_length: ?usize = null;

        for (first_segments) |seg1| {
            for (second_segments) |seg2| {
                if (findIntersection(seg1, seg2)) |intersection| {
                    const manhattan: u32 = @intCast(@abs(intersection.point.x) + @abs(intersection.point.y));

                    compareAndSetClosest(&closest_manhattan, manhattan);
                    compareAndSetClosest(&closest_path_length, intersection.steps);
                }
            }
        }

        return .{
            .closest_manhattan = closest_manhattan orelse return error.NoCrossingsFound,
            .closest_path_length = @intCast(closest_path_length orelse return error.NoCrossingsFound),
        };
    }
};

const Point = struct {
    x: i32,
    y: i32,
};

const Segment = struct {
    start: Point,
    end: Point,
    steps_to_start: usize,
};

fn buildSegments(allocator: Allocator, wire: []WireSegment) ![]Segment {
    var segments = try std.ArrayList(Segment).initCapacity(allocator, wire.len);
    var pos = Point{ .x = 0, .y = 0 };
    var steps: usize = 0;

    for (wire) |seg| {
        const start = pos;
        const steps_to_start = steps;

        switch (seg.direction) {
            .Up => pos.y += @intCast(seg.length),
            .Down => pos.y -= @intCast(seg.length),
            .Left => pos.x -= @intCast(seg.length),
            .Right => pos.x += @intCast(seg.length),
        }
        steps += seg.length;

        try segments.append(allocator, .{
            .start = start,
            .end = pos,
            .steps_to_start = steps_to_start,
        });
    }

    return segments.toOwnedSlice(allocator);
}

fn findIntersection(seg1: Segment, seg2: Segment) ?struct {
    point: Point,
    steps: usize,
} {
    const is_seg1_horizontal = seg1.start.y == seg1.end.y;
    const is_seg2_horizontal = seg2.start.y == seg2.end.y;

    if (is_seg1_horizontal == is_seg2_horizontal) return null;

    const h_seg = if (is_seg1_horizontal) seg1 else seg2;
    const v_seg = if (is_seg1_horizontal) seg2 else seg1;

    const h_min_x = @min(h_seg.start.x, h_seg.end.x);
    const h_max_x = @max(h_seg.start.x, h_seg.end.x);
    const v_min_y = @min(v_seg.start.y, v_seg.end.y);
    const v_max_y = @max(v_seg.start.y, v_seg.end.y);

    if (v_seg.start.x >= h_min_x and v_seg.start.x <= h_max_x and
        h_seg.start.y >= v_min_y and h_seg.start.y <= v_max_y)
    {
        // x from vertical, y from horizontal
        const intersection = Point{
            .x = v_seg.start.x,
            .y = h_seg.start.y,
        };

        if (intersection.x == 0 and intersection.y == 0) return null;

        const h_steps = h_seg.steps_to_start +
            @as(usize, @intCast(@abs(intersection.x - h_seg.start.x)));
        const v_steps = v_seg.steps_to_start +
            @as(usize, @intCast(@abs(intersection.y - v_seg.start.y)));

        return .{
            .point = intersection,
            .steps = h_steps + v_steps,
        };
    }

    return null;
}

fn parse(allocator: Allocator, input: *std.Io.Reader) !Wires {
    var first_line = std.Io.Writer.Allocating.init(allocator);
    defer first_line.deinit();
    _ = try input.streamDelimiter(&first_line.writer, '\n');
    _ = try input.discardAll(1);
    var second_line = std.Io.Writer.Allocating.init(allocator);
    defer second_line.deinit();
    _ = try input.streamDelimiterEnding(&second_line.writer, '\n');
    const first_wire = try parseWire(allocator, first_line.written());
    const second_wire = try parseWire(allocator, second_line.written());

    return Wires{
        .first = first_wire,
        .second = second_wire,
    };
}

fn parseWire(allocator: Allocator, line: []const u8) ![]WireSegment {
    var segments = try std.ArrayList(WireSegment).initCapacity(allocator, line.len / 2);
    var tokens = std.mem.tokenizeAny(u8, line, ",");

    while (tokens.next()) |token| {
        const segment = try parseSegment(token);
        try segments.appendBounded(segment);
    }
    return try segments.toOwnedSlice(allocator);
}

fn parseSegment(segment_str: []const u8) !WireSegment {
    if (segment_str.len < 2) {
        return error.InvalidSegment;
    }
    const dir_char = segment_str[0];
    const length_str = segment_str[1..];
    const length = try std.fmt.parseInt(u32, length_str, 10);
    const diection = switch (dir_char) {
        'U' => Direction.Up,
        'D' => Direction.Down,
        'L' => Direction.Left,
        'R' => Direction.Right,
        else => return error.InvalidDirection,
    };
    return WireSegment{
        .direction = diection,
        .length = length,
    };
}

test "parse segment" {
    const segment_str: []const u8 = "R75";
    const segment = try parseSegment(segment_str);
    try std.testing.expectEqual(.Right, segment.direction);
    try std.testing.expectEqual(75, segment.length);
}

test "parse wire" {
    const allocator = std.testing.allocator;
    const line: []const u8 = "R75,D30,L83,U83,R12";
    const segments = try parseWire(allocator, line);
    defer allocator.free(segments);

    try std.testing.expectEqual(5, segments.len);
    try std.testing.expectEqual(.Right, segments[0].direction);
    try std.testing.expectEqual(75, segments[0].length);
    try std.testing.expectEqual(.Down, segments[1].direction);
    try std.testing.expectEqual(30, segments[1].length);
    try std.testing.expectEqual(.Left, segments[2].direction);
    try std.testing.expectEqual(83, segments[2].length);
    try std.testing.expectEqual(.Up, segments[3].direction);
    try std.testing.expectEqual(83, segments[3].length);
    try std.testing.expectEqual(.Right, segments[4].direction);
    try std.testing.expectEqual(12, segments[4].length);
}

test "example" {
    const example_input: []const u8 =
        \\R8,U5,L5,D3
        \\U7,R6,D4,L4
        \\
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "6",
        "30",
    );
}
