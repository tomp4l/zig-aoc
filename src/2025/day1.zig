const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const turns = try parseInstructions(allocator, input);
    defer allocator.free(turns);

    const zero_counts = countZeros(turns);
    try solution.part1(zero_counts.zeroes_after_turns);
    try solution.part2(zero_counts.zeroes_passed_by);
}

const Lock = struct {
    const STARTING_POSITION = 50;
    position: u16 = STARTING_POSITION,
    zero_passes: u32 = 0,

    fn turn(self: *Lock, t: Turn) void {
        const direction = t.direction;

        const rotations = t.steps / 100;
        const remaining = t.steps % 100;
        self.zero_passes += @intCast(rotations);

        switch (direction) {
            .Left => {
                if (self.position < remaining) {
                    if (self.position != 0) {
                        self.zero_passes += 1;
                    }
                    self.position += 100 - remaining;
                } else {
                    self.position -= remaining;
                    if (self.position == 0) {
                        self.zero_passes += 1;
                    }
                }
            },
            .Right => {
                self.position += remaining;
                if (self.position >= 100) {
                    self.position -= 100;
                    self.zero_passes += 1;
                }
            },
        }
    }
};

fn countZeros(turns: []const Turn) struct { zeroes_after_turns: u32, zeroes_passed_by: u32 } {
    var lock = Lock{};
    var zero_count: u32 = 0;

    for (turns) |t| {
        lock.turn(t);
        if (lock.position == 0) {
            zero_count += 1;
        }
    }

    return .{ .zeroes_after_turns = zero_count, .zeroes_passed_by = lock.zero_passes };
}

const TurnDirection = enum {
    Left,
    Right,
};

const Turn = struct {
    direction: TurnDirection,
    steps: u16,
};

fn parseInstructions(allocator: Allocator, input: *std.Io.Reader) ![]Turn {
    var turns = try std.ArrayList(Turn).initCapacity(allocator, 100);

    while (try input.takeDelimiter('\n')) |part| {
        if (part.len < 2) {
            return error.InvalidInstruction;
        }
        const dir_char = part[0];
        const steps_str = part[1..];
        const steps = try std.fmt.parseInt(u16, steps_str, 10);

        const direction: TurnDirection =
            switch (dir_char) {
                'L' => .Left,
                'R' => .Right,
                else => return error.InvalidDirection,
            };

        try turns.append(allocator, .{ .direction = direction, .steps = steps });
    }

    return turns.toOwnedSlice(allocator);
}

test "left turn wraps through zero" {
    var lock = Lock{ .position = 5 };
    lock.turn(.{ .direction = .Left, .steps = 10 });
    try std.testing.expectEqual(95, lock.position);
    try std.testing.expectEqual(1, lock.zero_passes);
}

test "left turn ends at zero" {
    var lock = Lock{ .position = 10 };
    lock.turn(.{ .direction = .Left, .steps = 10 });
    try std.testing.expectEqual(0, lock.position);
    try std.testing.expectEqual(1, lock.zero_passes);
}

test "left turn from zero does not count" {
    var lock = Lock{ .position = 0 };
    lock.turn(.{ .direction = .Left, .steps = 10 });
    try std.testing.expectEqual(90, lock.position);
    try std.testing.expectEqual(0, lock.zero_passes);
}

test "right turn wraps through zero" {
    var lock = Lock{ .position = 95 };
    lock.turn(.{ .direction = .Right, .steps = 10 });
    try std.testing.expectEqual(5, lock.position);
    try std.testing.expectEqual(1, lock.zero_passes);
}

test "right turn ends at zero counts as passing" {
    var lock = Lock{ .position = 90 };
    lock.turn(.{ .direction = .Right, .steps = 10 });
    try std.testing.expectEqual(0, lock.position);
    try std.testing.expectEqual(1, lock.zero_passes);
}

test "full rotations count as zero passes" {
    var lock = Lock{ .position = 50 };
    lock.turn(.{ .direction = .Right, .steps = 250 });
    try std.testing.expectEqual(0, lock.position);
    try std.testing.expectEqual(3, lock.zero_passes);
}

test "example" {
    const example_input: []const u8 =
        \\L68
        \\L30
        \\R48
        \\L5
        \\R60
        \\L55
        \\L1
        \\L99
        \\R14
        \\L82
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "3",
        "6",
    );
}
