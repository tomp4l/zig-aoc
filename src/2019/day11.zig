const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const Intcode = @import("Intcode.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);

    {
        var hull = try PaintingHull.init(allocator, program);
        defer hull.deinit();
        try hull.paint();
        try solution.part1(hull.panels.count());
    }

    {
        var hull = try PaintingHull.init(allocator, program);
        defer hull.deinit();
        _ = try hull.panels.put(.{ .x = 0, .y = 0 }, true);
        try hull.paint();
        const output = try hull.toString(allocator);
        defer allocator.free(output);
        try solution.part2(output);
    }
}

const Direction = enum {
    Up,
    Right,
    Down,
    Left,
};
const Position = struct {
    x: i32,
    y: i32,
};

const PaintingHull = struct {
    panels: std.AutoHashMap(Position, bool),
    position: Position,
    direction: Direction,
    brain: Intcode,

    pub fn init(allocator: Allocator, program: []const Intcode.int_t) !PaintingHull {
        const brain = try Intcode.init(allocator, program);

        return PaintingHull{
            .panels = std.AutoHashMap(Position, bool).init(allocator),
            .position = Position{ .x = 0, .y = 0 },
            .direction = Direction.Up,
            .brain = brain,
        };
    }

    pub fn deinit(self: *PaintingHull) void {
        self.panels.deinit();
        self.brain.deinit();
    }

    pub fn paint(self: *PaintingHull) !void {
        _ = try self.brain.run();

        while (true) {
            const current_color: Intcode.int_t = @intFromBool(self.panels.get(self.position) orelse false);
            const halted = try self.brain.provideInputAndRun(current_color);
            if (halted) break;

            const paint_color = self.brain.getPreviousOutput(1);
            const turn_direction = self.brain.getPreviousOutput(0);

            try self.panels.put(self.position, paint_color == 1);

            self.direction = switch (self.direction) {
                .Up => if (turn_direction == 0) .Left else .Right,
                .Right => if (turn_direction == 0) .Up else .Down,
                .Down => if (turn_direction == 0) .Right else .Left,
                .Left => if (turn_direction == 0) .Down else .Up,
            };

            switch (self.direction) {
                .Up => self.position.y -= 1,
                .Right => self.position.x += 1,
                .Down => self.position.y += 1,
                .Left => self.position.x -= 1,
            }
        }
    }

    fn toString(self: *PaintingHull, allocator: Allocator) ![]const u8 {
        var min_x: i32 = 0;
        var max_x: i32 = 0;
        var min_y: i32 = 0;
        var max_y: i32 = 0;

        var it = self.panels.keyIterator();
        while (it.next()) |pos| {
            if (pos.x < min_x) min_x = pos.x;
            if (pos.x > max_x) max_x = pos.x;
            if (pos.y < min_y) min_y = pos.y;
            if (pos.y > max_y) max_y = pos.y;
        }

        var output = try std.ArrayList(u8).initCapacity(
            allocator,
            @intCast((max_x - min_x + 1) * (max_y - min_y + 1) + (max_y - min_y + 1)),
        );
        try output.append(allocator, '\n');
        for (0..@intCast(max_y - min_y + 1)) |y| {
            for (0..@intCast(max_x - min_x + 1)) |x| {
                const color = self.panels.get(.{
                    .x = @as(i32, @intCast(x)) + min_x,
                    .y = @as(i32, @intCast(y)) + min_y,
                }) orelse false;

                if (color) {
                    try output.append(allocator, '#');
                } else {
                    try output.append(allocator, ' ');
                }
            }
            try output.append(allocator, '\n');
        }

        return output.toOwnedSlice(allocator);
    }
};
test "example" {
    const example_input: []const u8 =
        \\3,100,104,1,104,1,3,100,99
    ;

    const expected_output =
        \\Part 1: 1
        \\Part 2: 
        \\#
        \\
        \\
    ;
    try testing.assertSolution(
        run,
        example_input,
        expected_output,
    );
}
