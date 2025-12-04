const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const Intcode = @import("./Intcode.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var scaffolding = try ScaffoldingProgram.fromInput(allocator, input);
    defer scaffolding.deinit(allocator);
    const alignment_sum = try scaffolding.sumAlignmentParameters(allocator);
    try solution.part1(alignment_sum);
    const dust_reported = try scaffolding.reportDust(allocator);
    try solution.part2(dust_reported);
}

const ScaffoldingProgram = struct {
    program: []const i64,
    scaffolding: Scaffolding,

    fn fromInput(allocator: Allocator, input: *std.Io.Reader) !@This() {
        const program = try Intcode.parseProgram(allocator, input);
        const scaffolding = try Scaffolding.fromIntcode(allocator, program);
        return .{
            .program = program,
            .scaffolding = scaffolding,
        };
    }

    fn sumAlignmentParameters(self: *@This(), allocator: Allocator) !i32 {
        const paths = try self.scaffolding.extractPaths(allocator);
        defer allocator.free(paths);

        var alignment_sum: i32 = 0;
        for (paths, 1..) |path1, i| {
            for (i..paths.len) |j| {
                const path2 = paths[j];
                if (path1.intersection(path2)) |coord| {
                    alignment_sum += coord.x * coord.y;
                }
            }
        }

        return alignment_sum;
    }

    fn reportDust(self: *@This(), allocator: Allocator) !usize {
        const paths = try self.scaffolding.extractPaths(allocator);
        defer allocator.free(paths);

        var commands = try Commands.fromPath(allocator, .Up, paths);
        defer commands.deinit(allocator);

        var command_groups = try commands.toCommandGroups(allocator);
        defer command_groups.deinit(allocator);

        var duped = try allocator.dupe(i64, self.program);
        defer allocator.free(duped);
        duped[0] = 2;
        var cpu = try Intcode.init(allocator, duped);
        defer cpu.deinit();
        try command_groups.output(&cpu, false);

        return @intCast(cpu.getLastOutput());
    }

    fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.program);
        self.scaffolding.deinit();
    }
};

const Tile = enum(u8) {
    Scaffold = '#',
    Empty = '.',
    RobotUp = '^',
    RobotDown = 'v',
    RobotLeft = '<',
    RobotRight = '>',
    RobotTumbling = 'X',
    _,

    fn isRobot(self: @This()) bool {
        return switch (self) {
            .RobotUp, .RobotDown, .RobotLeft, .RobotRight, .RobotTumbling => true,
            else => false,
        };
    }
};

const Coord = struct {
    x: i32,
    y: i32,

    fn next(self: @This(), direction: Direction) @This() {
        return self.nextN(direction, 1);
    }

    fn nextN(self: @This(), direction: Direction, n: i32) @This() {
        return switch (direction) {
            .Up => .{ .x = self.x, .y = self.y - n },
            .Down => .{ .x = self.x, .y = self.y + n },
            .Left => .{ .x = self.x - n, .y = self.y },
            .Right => .{ .x = self.x + n, .y = self.y },
        };
    }
};

const Direction = enum {
    Up,
    Down,
    Left,
    Right,

    fn left(self: @This()) @This() {
        return switch (self) {
            .Up => .Left,
            .Down => .Right,
            .Left => .Down,
            .Right => .Up,
        };
    }

    fn right(self: @This()) @This() {
        return switch (self) {
            .Up => .Right,
            .Down => .Left,
            .Left => .Up,
            .Right => .Down,
        };
    }
};

const Path = struct {
    start: Coord,
    distance: u32,
    direction: Direction,

    fn endExclusive(self: @This()) Coord {
        return self.start.nextN(self.direction, @intCast(self.distance - 1));
    }

    fn isHorizontal(self: @This()) bool {
        return self.direction == .Left or self.direction == .Right;
    }

    fn intersection(self: @This(), other: @This()) ?Coord {
        const self_is_horiz = self.isHorizontal();
        const other_is_horiz = other.isHorizontal();

        if (self_is_horiz == other_is_horiz) return null;

        const horiz = if (self_is_horiz) self else other;
        const vert = if (self_is_horiz) other else self;

        const horiz_min_x = @min(horiz.start.x, horiz.endExclusive().x);
        const horiz_max_x = @max(horiz.start.x, horiz.endExclusive().x);
        const vert_min_y = @min(vert.start.y, vert.endExclusive().y);
        const vert_max_y = @max(vert.start.y, vert.endExclusive().y);

        if (vert.start.x >= horiz_min_x and vert.start.x <= horiz_max_x and
            horiz.start.y >= vert_min_y and horiz.start.y <= vert_max_y)
        {
            return .{
                .x = vert.start.x,
                .y = horiz.start.y,
            };
        }
        return null;
    }
};

const Scaffolding = struct {
    tile_map: std.AutoHashMap(Coord, Tile),
    robot_position: Coord,

    fn fromIntcode(allocator: Allocator, program: []const i64) !@This() {
        var cpu = try Intcode.init(allocator, program);
        defer cpu.deinit();

        var tile_map = std.AutoHashMap(Coord, Tile).init(allocator);

        var x: i32 = 0;
        var y: i32 = 0;
        _ = try cpu.run();
        var robot_position: ?Coord = null;
        while (cpu.getNextOutput()) |output| {
            if (output == '\n') {
                x = 0;
                y += 1;
            } else {
                const tile: Tile = @enumFromInt(output);
                try tile_map.put(.{ .x = x, .y = y }, tile);

                if (tile.isRobot()) {
                    robot_position = .{ .x = x, .y = y };
                }

                x += 1;
            }
        }

        return .{
            .tile_map = tile_map,
            .robot_position = robot_position orelse return error.MissingRobot,
        };
    }

    fn extractPaths(self: *const @This(), allocator: Allocator) ![]Path {
        var result: std.ArrayList(Path) = .empty;
        errdefer result.deinit(allocator);

        var start = self.robot_position;
        var current = self.robot_position;

        var direction: Direction = undefined;
        inline for (@typeInfo(Direction).@"enum".fields) |dir_field| {
            const dir: Direction = @enumFromInt(dir_field.value);
            if (self.tile_map.get(current.next(dir)) orelse Tile.Empty == Tile.Scaffold) {
                direction = dir;
                break;
            }
        } else {
            return error.NoInitialDirection;
        }

        var distance: u32 = 0;

        while (true) {
            const next_coord = current.next(direction);
            const next_tile = self.tile_map.get(next_coord) orelse Tile.Empty;
            if (next_tile == Tile.Scaffold) {
                distance += 1;
                current = next_coord;
            } else {
                if (distance > 0) {
                    try result.append(allocator, .{ .start = start, .distance = distance, .direction = direction });
                    distance = 0;
                    start = current;
                }

                const left_direction = direction.left();
                const left_coord = current.next(left_direction);
                const left_tile = self.tile_map.get(left_coord) orelse Tile.Empty;

                const right_direction = direction.right();
                const right_coord = current.next(right_direction);
                const right_tile = self.tile_map.get(right_coord) orelse Tile.Empty;

                if (left_tile == Tile.Scaffold) {
                    direction = left_direction;
                } else if (right_tile == Tile.Scaffold) {
                    direction = right_direction;
                } else {
                    break;
                }
            }
        }

        return result.toOwnedSlice(allocator);
    }

    fn deinit(self: *@This()) void {
        self.tile_map.deinit();
    }

    fn debugPrint(self: *const @This()) void {
        var min_x: i32 = 0;
        var max_x: i32 = 0;
        var min_y: i32 = 0;
        var max_y: i32 = 0;

        var it = self.tile_map.keyIterator();
        while (it.next()) |pos| {
            if (pos.x < min_x) min_x = pos.x;
            if (pos.x > max_x) max_x = pos.x;
            if (pos.y < min_y) min_y = pos.y;
            if (pos.y > max_y) max_y = pos.y;
        }

        for (0..@intCast(max_y - min_y + 1)) |yy| {
            const y = min_y + @as(i32, @intCast(yy));
            for (0..@intCast(max_x - min_x + 1)) |xx| {
                const x = min_x + @as(i32, @intCast(xx));
                const tile = self.tile_map.get(.{ .x = x, .y = y }) orelse Tile.Empty;
                std.debug.print("{c}", .{@as(u8, @intFromEnum(tile))});
            }
            std.debug.print("\n", .{});
        }
    }
};

const Turn = enum {
    Left,
    Right,
};
const Command = struct {
    turn: Turn,
    distance: u32,
};

const CommandGroup = struct {
    groups: [3][]Command,
    commands: []usize,

    fn deinit(self: *@This(), allocator: Allocator) void {
        for (self.groups) |cmds| {
            allocator.free(cmds);
        }
        allocator.free(self.commands);
    }

    fn output(self: *@This(), cpu: *Intcode, verbose: bool) !void {
        _ = try cpu.run();

        for (self.commands, 1..) |command, l| {
            const c = 'A' + @as(u8, @intCast(command));
            _ = try cpu.provideInputAndRun(@as(i64, c));
            if (l != self.commands.len) {
                _ = try cpu.provideInputAndRun(@as(i64, ','));
            } else {
                _ = try cpu.provideInputAndRun(@as(i64, '\n'));
            }
        }

        for (self.groups) |cmds| {
            for (cmds, 1..) |command, l| {
                const turn_char: u8 = switch (command.turn) {
                    .Left => 'L',
                    .Right => 'R',
                };
                _ = try cpu.provideInputAndRun(@as(i64, turn_char));
                _ = try cpu.provideInputAndRun(@as(i64, ','));
                var distance_buf: [2]u8 = undefined;
                const distance_str = try std.fmt.bufPrint(&distance_buf, "{}", .{command.distance});
                for (distance_str) |c| {
                    _ = try cpu.provideInputAndRun(@as(i64, c));
                }

                if (l < cmds.len) {
                    _ = try cpu.provideInputAndRun(@as(i64, ','));
                }
            }
            _ = try cpu.provideInputAndRun(@as(i64, '\n'));
        }

        const video_char: u8 = if (verbose) 'y' else 'n';
        _ = try cpu.provideInputAndRun(@as(i64, video_char));
        _ = try cpu.provideInputAndRun(@as(i64, '\n'));
    }
};

const Commands = struct {
    commands: []Command,

    const MAX_PATTERN_LENGTH = 7;
    const MAX_LINE_LENGTH = 20;

    fn fromPath(allocator: Allocator, robot_direction: Direction, paths: []const Path) !@This() {
        var result = try std.ArrayList(Command).initCapacity(allocator, 100);
        defer result.deinit(allocator);

        var current_direction = robot_direction;
        for (paths) |path| {
            const turn: Turn = if (current_direction.left() == path.direction) .Left else .Right;
            try result.append(allocator, .{ .turn = turn, .distance = path.distance });

            current_direction = path.direction;
        }

        return .{ .commands = try result.toOwnedSlice(allocator) };
    }

    fn toCommandGroups(self: *@This(), allocator: Allocator) !CommandGroup {
        for (1..MAX_PATTERN_LENGTH) |a_len| {
            const pattern_a = self.commands[0..a_len];
            var pos_after_a = a_len;
            while (pos_after_a < self.commands.len and self.matchesPattern(pos_after_a, pattern_a)) {
                pos_after_a += a_len;
            }

            if (pos_after_a >= self.commands.len) continue;

            for (1..MAX_PATTERN_LENGTH) |b_len| {
                const pattern_b = self.commands[pos_after_a .. pos_after_a + b_len];

                var pos: usize = 0;
                var found_c = false;
                var pattern_c_start: ?usize = null;

                while (pos < self.commands.len) {
                    if (self.matchesPattern(pos, pattern_a)) {
                        pos += a_len;
                    } else if (self.matchesPattern(pos, pattern_b)) {
                        pos += b_len;
                    } else {
                        pattern_c_start = pos;
                        found_c = true;
                        break;
                    }
                }

                if (!found_c) continue;

                for (1..MAX_PATTERN_LENGTH) |c_len| {
                    if (pattern_c_start.? + c_len > self.commands.len) break;

                    const pattern_c = self.commands[pattern_c_start.? .. pattern_c_start.? + c_len];

                    if (try self.tryPatterns(allocator, pattern_a, pattern_b, pattern_c)) |result| {
                        return result;
                    }
                }
            }
        }

        return error.NoValidPatternFound;
    }

    fn matchesPattern(self: *const @This(), pos: usize, pattern: []const Command) bool {
        if (pos + pattern.len > self.commands.len) return false;

        for (pattern, 0..) |cmd, i| {
            const actual = self.commands[pos + i];
            if (actual.turn != cmd.turn or actual.distance != cmd.distance) {
                return false;
            }
        }
        return true;
    }

    fn tryPatterns(self: *const @This(), allocator: Allocator, pattern_a: []const Command, pattern_b: []const Command, pattern_c: []const Command) !?CommandGroup {
        var command_sequence: std.ArrayList(usize) = .empty;
        defer command_sequence.deinit(allocator);

        var pos: usize = 0;
        while (pos < self.commands.len) {
            if (self.matchesPattern(pos, pattern_a)) {
                try command_sequence.append(allocator, 0);
                pos += pattern_a.len;
            } else if (self.matchesPattern(pos, pattern_b)) {
                try command_sequence.append(allocator, 1);
                pos += pattern_b.len;
            } else if (self.matchesPattern(pos, pattern_c)) {
                try command_sequence.append(allocator, 2);
                pos += pattern_c.len;
            } else {
                return null;
            }
        }

        if (command_sequence.items.len * 2 - 1 > MAX_LINE_LENGTH) return null;
        if (try patternLength(pattern_a) > MAX_LINE_LENGTH) return null;
        if (try patternLength(pattern_b) > MAX_LINE_LENGTH) return null;
        if (try patternLength(pattern_c) > MAX_LINE_LENGTH) return null;

        return CommandGroup{
            .groups = .{
                try allocator.dupe(Command, pattern_a),
                try allocator.dupe(Command, pattern_b),
                try allocator.dupe(Command, pattern_c),
            },
            .commands = try command_sequence.toOwnedSlice(allocator),
        };
    }

    fn patternLength(pattern: []const Command) !usize {
        var length: usize = 0;
        for (pattern) |cmd| {
            var distance_buf: [10]u8 = undefined;
            const distance_str = try std.fmt.bufPrint(&distance_buf, "{}", .{cmd.distance});
            length += distance_str.len;
        }
        length += pattern.len + pattern.len - 1; // commas and turns
        return length;
    }

    fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.commands);
    }
};

test "command groups" {
    const allocator = std.testing.allocator;

    const command_str = "R,8,R,8,R,4,R,4,R,8,L,6,L,2,R,4,R,4,R,8,R,8,R,8,L,6,L,2";

    var tokens = std.mem.splitScalar(u8, command_str, ',');
    var commands_list = try std.ArrayList(Command).initCapacity(allocator, 20);
    defer commands_list.deinit(allocator);
    while (tokens.next()) |token| {
        const turn_char = token;
        const distance_str = tokens.next() orelse return error.CrappyTestInput;
        const distance = try std.fmt.parseInt(u32, distance_str, 10);

        const turn: Turn = switch (turn_char[0]) {
            'L' => .Left,
            'R' => .Right,
            else => return error.InvalidDirection,
        };

        try commands_list.append(allocator, .{ .turn = turn, .distance = distance });
    }

    var commands = Commands{ .commands = try commands_list.toOwnedSlice(allocator) };
    defer commands.deinit(allocator);
    var command_groups = try commands.toCommandGroups(allocator);
    defer command_groups.deinit(allocator);

    try std.testing.expectEqualSlices(Command, command_groups.groups[0], &[_]Command{
        .{ .turn = .Right, .distance = 8 },
    });

    try std.testing.expectEqualSlices(Command, command_groups.groups[1], &[_]Command{
        .{ .turn = .Right, .distance = 4 },
        .{ .turn = .Right, .distance = 4 },
    });

    try std.testing.expectEqualSlices(Command, command_groups.groups[2], &[_]Command{
        .{ .turn = .Left, .distance = 6 },
        .{ .turn = .Left, .distance = 2 },
    });

    try std.testing.expectEqualSlices(usize, command_groups.commands, &[_]usize{ 0, 0, 1, 0, 2, 1, 0, 0, 0, 2 });
}
