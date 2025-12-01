const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const Intcode = @import("Intcode.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);
    var ship = try Ship.init(allocator, program);
    defer ship.deinit();
    try ship.exploreAll(allocator);

    const part1 = try ship.distanceToOxygenSystem(allocator);
    try solution.part1(part1);
    const part2 = try ship.fillWithOxygen(allocator);
    try solution.part2(part2);
}

const Position = struct {
    x: i32,
    y: i32,

    fn neighbours(self: Position) [4]Position {
        return .{
            .{ .x = self.x, .y = self.y - 1 },
            .{ .x = self.x, .y = self.y + 1 },
            .{ .x = self.x - 1, .y = self.y },
            .{ .x = self.x + 1, .y = self.y },
        };
    }
};

const SquareType = enum {
    Wall,
    Empty,
    OxygenSystem,
};

const DirectionCommand = enum(i32) {
    North = 1,
    South = 2,
    West = 3,
    East = 4,
};

const StatusCode = enum(i64) {
    HitWall = 0,
    Moved = 1,
    MovedAndFoundOxygenSystem = 2,
};

const Ship = struct {
    droid_position: Position = .{ .x = 0, .y = 0 },
    layout: std.AutoHashMap(Position, SquareType),
    unexplored: std.AutoHashMap(Position, void),
    droid: Intcode,

    fn init(allocator: Allocator, program: []const Intcode.int_t) !Ship {
        const brain = try Intcode.init(allocator, program);
        var layout = std.AutoHashMap(Position, SquareType).init(allocator);
        try layout.put(.{ .x = 0, .y = 0 }, .Empty);
        var unexplored = std.AutoHashMap(Position, void).init(allocator);
        try unexplored.put(.{ .x = 0, .y = -1 }, {});
        try unexplored.put(.{ .x = 0, .y = 1 }, {});
        try unexplored.put(.{ .x = -1, .y = 0 }, {});
        try unexplored.put(.{ .x = 1, .y = 0 }, {});

        return Ship{
            .layout = layout,
            .unexplored = unexplored,
            .droid = brain,
        };
    }

    fn deinit(self: *Ship) void {
        self.layout.deinit();
        self.droid.deinit();
        self.unexplored.deinit();
    }

    fn moveDroid(self: *Ship, direction: DirectionCommand) !void {
        _ = try self.droid.provideInputAndRun(@intFromEnum(direction));

        const status = self.droid.getLastOutput();
        const status_code: StatusCode = @enumFromInt(status);

        const new_position: Position = switch (direction) {
            .North => .{ .x = self.droid_position.x, .y = self.droid_position.y - 1 },
            .South => .{ .x = self.droid_position.x, .y = self.droid_position.y + 1 },
            .West => .{ .x = self.droid_position.x - 1, .y = self.droid_position.y },
            .East => .{ .x = self.droid_position.x + 1, .y = self.droid_position.y },
        };

        if (status_code == .Moved or status_code == .MovedAndFoundOxygenSystem) {
            self.droid_position = new_position;
        }

        const square_type: SquareType = switch (status_code) {
            .HitWall => .Wall,
            .Moved => .Empty,
            .MovedAndFoundOxygenSystem => .OxygenSystem,
        };

        try self.layout.put(new_position, square_type);
        const moved = self.droid_position.x == new_position.x and self.droid_position.y == new_position.y;
        _ = self.unexplored.remove(new_position);
        if (moved) {
            for (new_position.neighbours()) |neighbour| {
                if (self.layout.get(neighbour) == null) {
                    try self.unexplored.put(neighbour, {});
                }
            }
        }
    }

    fn exploreAll(self: *Ship, allocator: Allocator) !void {
        _ = try self.droid.run();
        while (self.unexplored.count() > 0) {
            var it = self.unexplored.keyIterator();
            var closest_position: ?Position = null;
            while (it.next()) |pos| {
                if (closest_position == null) {
                    closest_position = pos.*;
                } else {
                    const current_distance = @abs(closest_position.?.x - self.droid_position.x) +
                        @abs(closest_position.?.y - self.droid_position.y);
                    const candidate_distance = @abs(pos.*.x - self.droid_position.x) +
                        @abs(pos.*.y - self.droid_position.y);
                    if (candidate_distance < current_distance) {
                        closest_position = pos.*;
                    }
                }
            }
            const target_position = closest_position.?;
            const path = try self.pathTo(allocator, self.droid_position, target_position);
            defer allocator.free(path);
            for (path) |command| {
                try self.moveDroid(command);
            }
        }
    }

    fn pathTo(self: *const Ship, allocator: Allocator, from: Position, to: Position) ![]const DirectionCommand {
        const PossiblePath = struct {
            position: Position,
            commands: []const DirectionCommand,
            node: std.DoublyLinkedList.Node = .{},
        };
        var visited = std.AutoHashMap(Position, void).init(allocator);
        defer visited.deinit();

        var queue: std.DoublyLinkedList = .{};
        const start_node = try allocator.create(PossiblePath);
        start_node.* = PossiblePath{
            .position = from,
            .commands = &.{},
        };
        queue.append(&start_node.node);
        defer {
            while (queue.popFirst()) |node| {
                const path: *PossiblePath = @fieldParentPtr("node", node);
                allocator.free(path.commands);
                allocator.destroy(path);
            }
        }

        while (queue.popFirst()) |node| {
            const path: *PossiblePath = @fieldParentPtr("node", node);
            defer {
                allocator.free(path.commands);
                allocator.destroy(path);
            }
            if (path.position.x == to.x and path.position.y == to.y) {
                const duped = try allocator.dupe(DirectionCommand, path.commands);
                return duped;
            }
            if (visited.contains(path.position)) continue;
            try visited.put(path.position, {});
            for (Position.neighbours(path.position)) |neighbour_info| {
                const direction: DirectionCommand = if (neighbour_info.y < path.position.y)
                    .North
                else if (neighbour_info.y > path.position.y)
                    .South
                else if (neighbour_info.x < path.position.x)
                    .West
                else
                    .East;

                const square_type = self.layout.get(neighbour_info) orelse .Empty;
                if (square_type == .Wall) continue;
                const new_commands = try allocator.alloc(DirectionCommand, path.commands.len + 1);
                @memcpy(new_commands[0..path.commands.len], path.commands);
                new_commands[path.commands.len] = direction;
                const new_node = try allocator.create(PossiblePath);
                new_node.* = PossiblePath{
                    .position = neighbour_info,
                    .commands = new_commands,
                };
                queue.append(&new_node.node);
            }
        }
        return error.NoPath;
    }

    fn distanceToOxygenSystem(self: *const Ship, allocator: Allocator) !usize {
        var it = self.layout.keyIterator();
        var oxygen_position: ?Position = null;
        while (it.next()) |pos| {
            if (self.layout.get(pos.*) == .OxygenSystem) {
                oxygen_position = pos.*;
                break;
            }
        }
        if (oxygen_position == null) return error.NoOxygenSystem;

        const path = try self.pathTo(allocator, .{ .x = 0, .y = 0 }, oxygen_position.?);
        defer allocator.free(path);
        return path.len;
    }

    fn fillWithOxygen(self: *Ship, allocator: Allocator) !usize {
        var minutes: usize = 0;
        var oxygenated = std.AutoHashMap(Position, void).init(allocator);
        defer oxygenated.deinit();

        var newly_oxygenated = std.AutoHashMap(Position, void).init(allocator);
        defer newly_oxygenated.deinit();

        var layout_it = self.layout.keyIterator();
        while (layout_it.next()) |pos| {
            if (self.layout.get(pos.*) == .OxygenSystem) {
                try newly_oxygenated.put(pos.*, {});
                break;
            }
        }

        while (newly_oxygenated.count() > 0) {
            var next_newly_oxygenated = std.AutoHashMap(Position, void).init(allocator);
            defer next_newly_oxygenated.deinit();

            var it = newly_oxygenated.keyIterator();
            while (it.next()) |pos| {
                for (pos.neighbours()) |neighbour| {
                    if (self.layout.get(neighbour) == .Empty and
                        !oxygenated.contains(neighbour) and
                        !newly_oxygenated.contains(neighbour))
                    {
                        try next_newly_oxygenated.put(neighbour, {});
                    }
                }
                try oxygenated.put(pos.*, {});
            }
            newly_oxygenated.deinit();
            newly_oxygenated = next_newly_oxygenated;
            next_newly_oxygenated = std.AutoHashMap(Position, void).init(allocator);

            if (newly_oxygenated.count() > 0) {
                minutes += 1;
            }
        }

        return minutes;
    }
};
