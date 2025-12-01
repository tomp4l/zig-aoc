const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var asteroids = try Asteroids.parse(allocator, input);
    defer asteroids.deinit(allocator);

    const result = try asteroids.mostVisibleAndTarget(allocator, 200);
    try solution.part1(result.visible_count);
    const part2_result = result.point.x * 100 + result.point.y;
    try solution.part2(part2_result);
}

const Vector = struct {
    x: i16,
    y: i16,

    fn diff(self: Vector, other: Vector) Vector {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    fn reduce(self: Vector) Vector {
        const gcd: i16 = @intCast(std.math.gcd(@abs(self.x), @abs(self.y)));
        if (gcd == 0) {
            return self;
        } else {
            return .{ .x = @divExact(self.x, gcd), .y = @divExact(self.y, gcd) };
        }
    }

    fn lessThanClockwiseFromUp(context: void, a: Vector, b: Vector) bool {
        _ = context;

        var angle_a = std.math.atan2(@as(f64, @floatFromInt(a.x)), @as(f64, @floatFromInt(-a.y)));
        var angle_b = std.math.atan2(@as(f64, @floatFromInt(b.x)), @as(f64, @floatFromInt(-b.y)));

        if (angle_a < 0) angle_a += 2.0 * std.math.pi;
        if (angle_b < 0) angle_b += 2.0 * std.math.pi;

        return angle_a < angle_b;
    }
};

const Asteroids = struct {
    points: std.ArrayList(Vector),
    width: i16 = 0,
    height: i16 = 0,

    pub fn parse(allocator: Allocator, reader: *std.Io.Reader) !Asteroids {
        var asteroids = Asteroids{
            .points = try std.ArrayList(Vector).initCapacity(allocator, 128),
        };

        var row: i16 = 0;
        var col: i16 = 0;
        while (true) {
            var line_writer = std.Io.Writer.Allocating.init(allocator);
            defer line_writer.deinit();
            const line_length = try reader.streamDelimiterEnding(&line_writer.writer, '\n');
            if (line_length == 0) break;

            for (line_writer.written()) |c| {
                if (c == '#') {
                    try asteroids.points.append(allocator, .{ .x = col, .y = row });
                }
                col += 1;
            }
            asteroids.width = col;
            row += 1;
            col = 0;
            reader.discardAll(1) catch break;
        }
        asteroids.height = row;

        return asteroids;
    }

    const Result = struct {
        point: Vector,
        visible_count: usize,
    };

    fn findVisibleAsteroidsFrom(self: Asteroids, allocator: Allocator, from: Vector) ![]Vector {
        var visible = std.AutoHashMap(Vector, Vector).init(allocator);
        defer visible.deinit();

        for (self.points.items) |to| {
            if (to.x == from.x and to.y == from.y) continue;

            const direction = to.diff(from).reduce();

            if (visible.get(direction)) |existing| {
                const existing_diff = existing.diff(from);
                const to_diff = to.diff(from);
                const existing_dist_sq = existing_diff.x * existing_diff.x + existing_diff.y * existing_diff.y;
                const to_dist_sq = to_diff.x * to_diff.x + to_diff.y * to_diff.y;
                if (to_dist_sq < existing_dist_sq) {
                    try visible.put(direction, to);
                }
            } else {
                try visible.put(direction, to);
            }
        }

        var it = visible.valueIterator();
        var output = try allocator.alloc(Vector, visible.count());
        var index: usize = 0;
        while (it.next()) |key| {
            output[index] = key.*;
            index += 1;
        }

        return output;
    }

    fn mostVisibleAndTarget(self: Asteroids, allocator: Allocator, target: usize) !Result {
        var max_visible: []Vector = &.{};
        var best_location: Vector = .{ .x = 0, .y = 0 };
        defer allocator.free(max_visible);

        for (self.points.items) |from| {
            const visible = try self.findVisibleAsteroidsFrom(allocator, from);
            if (visible.len > max_visible.len) {
                allocator.free(max_visible);
                max_visible = visible;
                best_location = from;
            } else {
                allocator.free(visible);
            }
        }

        if (target > max_visible.len) return error.OutOfBounds;

        for (max_visible) |*vector| {
            vector.* = vector.diff(best_location);
        }

        std.mem.sort(Vector, max_visible, {}, Vector.lessThanClockwiseFromUp);
        const target_vector = max_visible[target - 1];
        const target_point: Vector = Vector{
            .x = best_location.x + target_vector.x,
            .y = best_location.y + target_vector.y,
        };

        return .{ .point = target_point, .visible_count = max_visible.len };
    }

    fn deinit(self: *Asteroids, allocator: Allocator) void {
        self.points.deinit(allocator);
    }
};

test "example" {
    const example_input: []const u8 =
        \\.#..##.###...#######
        \\##.############..##.
        \\.#.######.########.#
        \\.###.#######.####.#.
        \\#####.##.#.##.###.##
        \\..#####..#.#########
        \\####################
        \\#.####....###.#.#.##
        \\##.#################
        \\#####.##.###..####..
        \\..######..##.#######
        \\####.##.####...##..#
        \\.#####..#.######.###
        \\##...#.##########...
        \\#.##########.#######
        \\.####.#.###.###.#.##
        \\....##.##.###..#####
        \\.#.#.###########.###
        \\#.#.#.#####.####.###
        \\###.##.####.##.#..##
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "210",
        "802",
    );
}

test "less than" {
    const a = Vector{ .x = 0, .y = -1 };
    const b = Vector{ .x = 1, .y = 0 };
    const c = Vector{ .x = 0, .y = 1 };
    const d = Vector{ .x = -1, .y = 0 };

    const e = Vector{ .x = -1, .y = -1 };

    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, a, b) == true);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, a, c) == true);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, a, d) == true);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, a, e) == true);

    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, b, a) == false);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, b, c) == true);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, b, d) == true);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, b, e) == true);

    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, c, a) == false);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, c, b) == false);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, c, d) == true);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, c, e) == true);

    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, d, a) == false);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, d, b) == false);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, d, c) == false);
    try std.testing.expect(Vector.lessThanClockwiseFromUp({}, d, e) == true);
}
