const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const Intcode = @import("Intcode.zig");

const VISUALISE = false;

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const program = try Intcode.parseProgram(allocator, input);
    defer allocator.free(program);

    try solution.part1(try countBlocks(allocator, program));
    try solution.part2(try runToEnd(allocator, program));
}

fn countBlocks(allocator: Allocator, program: []Intcode.int_t) !u32 {
    var cabinet = try Cabinet.init(allocator, program);
    defer cabinet.deinit();

    const done = try cabinet.runToInput();
    std.debug.assert(done);

    return cabinet.countBlocks();
}

fn runToEnd(allocator: Allocator, program: []Intcode.int_t) !u64 {
    var cabinet = try Cabinet.init(allocator, program);
    try cabinet.cpu.setMemory(0, 2);
    defer cabinet.deinit();

    while (!try cabinet.runToInput()) {
        try cabinet.movePaddleToBall();
    }

    return cabinet.score;
}

const Square = enum(u8) {
    TileEmpty = 0,
    TileWall = 1,
    TileBlock = 2,
    TilePaddle = 3,
    TileBall = 4,
};

const Coord = struct {
    x: u32,
    y: u32,
};

const PaddleMovement = enum(i64) {
    Left = -1,
    Neutral = 0,
    Right = 1,
};

const Cabinet = struct {
    cpu: Intcode,
    screen: std.AutoHashMap(Coord, Square),
    score: u64 = 0,
    ball_x_pos: ?u32 = null,
    paddle_x_pos: ?u32 = null,

    fn init(allocator: Allocator, program: []const Intcode.int_t) !Cabinet {
        const cpu = try Intcode.init(allocator, program);
        return Cabinet{
            .cpu = cpu,
            .screen = std.AutoHashMap(Coord, Square).init(allocator),
        };
    }

    fn deinit(self: *Cabinet) void {
        self.cpu.deinit();
        self.screen.deinit();
    }

    fn runToInput(self: *Cabinet) !bool {
        const finished = try self.cpu.run();
        while (true) {
            const x = self.cpu.getNextOutput() orelse break;
            const y = try (self.cpu.getNextOutput() orelse error.UnexpectedEndOfOutput);
            const tile_id = try (self.cpu.getNextOutput() orelse error.UnexpectedEndOfOutput);
            if (x == -1 and y == 0) {
                self.score = @intCast(tile_id);
                continue;
            }
            const tile: Square = @enumFromInt(tile_id);
            if (tile == .TileBall) {
                self.ball_x_pos = @intCast(x);
            } else if (tile == .TilePaddle) {
                self.paddle_x_pos = @intCast(x);
            }

            try self.screen.put(.{ .x = @intCast(x), .y = @intCast(y) }, tile);

            if (VISUALISE) {
                if (tile == .TilePaddle) try self.debugPrintScreen();
            }
        }
        return finished;
    }

    fn countBlocks(self: *const Cabinet) u32 {
        var count: u32 = 0;
        var it = self.screen.valueIterator();
        while (it.next()) |entry| {
            if (entry.* == .TileBlock) {
                count += 1;
            }
        }
        return count;
    }

    fn movePaddleToBall(self: *Cabinet) !void {
        const paddle_x = self.paddle_x_pos orelse return error.MissingPaddle;
        const target_x = self.ball_x_pos orelse return error.MissingBall;

        const movement: PaddleMovement = switch (std.math.order(paddle_x, target_x)) {
            .lt => .Right, // paddle < target, move right
            .gt => .Left, // paddle > target, move left
            .eq => .Neutral,
        };
        _ = try self.cpu.provideInput(@intFromEnum(movement));
    }

    fn debugPrintScreen(self: *const Cabinet) !void {
        var min_x: u32 = 0;
        var max_x: u32 = 0;
        var min_y: u32 = 0;
        var max_y: u32 = 0;

        var it = self.screen.keyIterator();
        while (it.next()) |coord| {
            min_x = @min(min_x, coord.x);
            max_x = @max(max_x, coord.x);
            min_y = @min(min_y, coord.y);
            max_y = @max(max_y, coord.y);
        }

        var buffer: [1024 * 8]u8 = undefined;
        var buffer_writer = std.Io.Writer.fixed(&buffer);

        // ANSI color codes: 31=red, 32=green, 33=yellow, 34=blue, 35=magenta, 36=cyan
        const block_colors = [_]u8{ 31, 32, 33, 34, 35, 36 };

        for (min_y..max_y + 1) |y| {
            for (min_x..max_x + 1) |x| {
                const square = self.screen.get(.{ .x = @intCast(x), .y = @intCast(y) }) orelse .TileEmpty;

                if (square == .TileBlock) {
                    const color_idx = std.hash.int(x + y * 1000) % block_colors.len;
                    try buffer_writer.print("\x1B[{d}m▓\x1B[0m", .{block_colors[color_idx]});
                } else {
                    const char: []const u8 = switch (square) {
                        .TileEmpty => " ",
                        .TileWall => "█",
                        .TileBlock => unreachable, // handled above
                        .TilePaddle => "▬",
                        .TileBall => "●",
                    };
                    try buffer_writer.print("{s}", .{char});
                }
            }
            try buffer_writer.print("\n", .{});
        }

        try buffer_writer.print("Score: {}\n", .{self.score});
        std.debug.print("\x1B[2J\x1B[H{s}", .{buffer_writer.buffered()});

        std.Thread.sleep(66_000_000);
    }
};
