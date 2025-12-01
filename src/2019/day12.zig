const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;
const lcm = std.math.lcm;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const moons = try parseMoons(allocator, input);
    defer allocator.free(moons);

    var system = System{ .moons = moons };
    system.simulate(1000);

    try solution.part1(system.totalEnergy());

    try solution.part2(cyclePeriod(moons));
}

fn cyclePeriod(moons: []const Moon) u64 {
    const cycle_x = findAxisCycle(moons, .X);
    const cycle_y = findAxisCycle(moons, .Y);
    const cycle_z = findAxisCycle(moons, .Z);

    return lcm(lcm(cycle_x, cycle_y), cycle_z);
}

const Vec3 = struct {
    x: i32,
    y: i32,
    z: i32,

    fn add(self: *Vec3, other: Vec3) void {
        self.x += other.x;
        self.y += other.y;
        self.z += other.z;
    }

    fn energy(self: Vec3) u32 {
        return @intCast(@abs(self.x) + @abs(self.y) + @abs(self.z));
    }
};

const Moon = struct {
    pos: Vec3,
    vel: Vec3 = .{ .x = 0, .y = 0, .z = 0 },

    fn applyGravity(self: *Moon, other: Moon) void {
        if (other.pos.x > self.pos.x) {
            self.vel.x += 1;
        } else if (other.pos.x < self.pos.x) {
            self.vel.x -= 1;
        }
        if (other.pos.y > self.pos.y) {
            self.vel.y += 1;
        } else if (other.pos.y < self.pos.y) {
            self.vel.y -= 1;
        }
        if (other.pos.z > self.pos.z) {
            self.vel.z += 1;
        } else if (other.pos.z < self.pos.z) {
            self.vel.z -= 1;
        }
    }

    fn energy(self: Moon) u32 {
        return self.pos.energy() * self.vel.energy();
    }
};

const System = struct {
    moons: []Moon,

    fn simulate(self: *System, steps: usize) void {
        for (0..steps) |_| {
            self.step();
        }
    }

    fn step(self: *System) void {
        for (0..self.moons.len) |i| {
            for (i + 1..self.moons.len) |j| {
                self.moons[i].applyGravity(self.moons[j]);
                self.moons[j].applyGravity(self.moons[i]);
            }
        }

        for (self.moons) |*moon| {
            moon.pos.add(moon.vel);
        }
    }

    fn totalEnergy(self: System) u32 {
        var total: u32 = 0;
        for (self.moons) |moon| {
            total += moon.energy();
        }
        return total;
    }
};

const Axis = enum { X, Y, Z };

const AxisState = struct {
    pos: [4]i32,
    vel: [4]i32,

    fn init(moons: []const Moon, ax: Axis) @This() {
        std.debug.assert(moons.len == 4);
        var state: @This() = undefined;
        for (moons, 0..) |moon, i| {
            state.pos[i] = switch (ax) {
                .X => moon.pos.x,
                .Y => moon.pos.y,
                .Z => moon.pos.z,
            };
            state.vel[i] = switch (ax) {
                .X => moon.vel.x,
                .Y => moon.vel.y,
                .Z => moon.vel.z,
            };
        }
        return state;
    }

    fn step(self: *@This()) void {
        for (0..4) |i| {
            for (i + 1..4) |j| {
                if (self.pos[j] > self.pos[i]) {
                    self.vel[i] += 1;
                    self.vel[j] -= 1;
                } else if (self.pos[j] < self.pos[i]) {
                    self.vel[i] -= 1;
                    self.vel[j] += 1;
                }
            }
        }
        for (0..4) |i| {
            self.pos[i] += self.vel[i];
        }
    }

    fn eql(self: @This(), other: @This()) bool {
        return std.mem.eql(i32, &self.pos, &other.pos) and
            std.mem.eql(i32, &self.vel, &other.vel);
    }
};

fn findAxisCycle(initial_moons: []const Moon, axis: Axis) u64 {
    const initial = AxisState.init(initial_moons, axis);
    var state = initial;
    var steps: u64 = 0;

    while (true) {
        state.step();
        steps += 1;
        if (state.eql(initial)) {
            return steps;
        }
    }
}

fn parseMoons(allocator: Allocator, input: *std.Io.Reader) ![]Moon {
    var moons = try std.ArrayList(Moon).initCapacity(allocator, 4);

    while (true) {
        var line_writer = std.Io.Writer.Allocating.init(allocator);
        defer line_writer.deinit();
        const line_length = try input.streamDelimiterEnding(&line_writer.writer, '\n');
        if (line_length == 0) break;

        const line = line_writer.written();
        const moon = try parseMoon(line);
        try moons.append(allocator, moon);

        input.discardAll(1) catch break;
    }

    return moons.toOwnedSlice(allocator);
}

fn parseMoon(line: []const u8) !Moon {
    var pos = Vec3{ .x = 0, .y = 0, .z = 0 };

    var it = std.mem.tokenizeAny(u8, line, "<>, ");
    while (it.next()) |token| {
        if (std.mem.startsWith(u8, token, "x=")) {
            pos.x = try std.fmt.parseInt(i32, token[2..], 10);
        } else if (std.mem.startsWith(u8, token, "y=")) {
            pos.y = try std.fmt.parseInt(i32, token[2..], 10);
        } else if (std.mem.startsWith(u8, token, "z=")) {
            pos.z = try std.fmt.parseInt(i32, token[2..], 10);
        }
    }

    return Moon{ .pos = pos };
}

test "example 1" {
    const example_input: []const u8 =
        \\<x=-1, y=0, z=2>
        \\<x=2, y=-10, z=-7>
        \\<x=4, y=-8, z=8>
        \\<x=3, y=5, z=-1>
    ;

    const allocator = std.testing.allocator;
    var reader = std.Io.Reader.fixed(example_input);

    const moons = try parseMoons(allocator, &reader);
    defer allocator.free(moons);

    var system = System{ .moons = moons };
    system.simulate(10);

    try std.testing.expectEqual(179, system.totalEnergy());
}

test "example 2" {
    const example_input: []const u8 =
        \\<x=-8, y=-10, z=0>
        \\<x=5, y=5, z=10>
        \\<x=2, y=-7, z=3>
        \\<x=9, y=-8, z=-3>
    ;

    const allocator = std.testing.allocator;
    var reader = std.Io.Reader.fixed(example_input);

    const moons = try parseMoons(allocator, &reader);
    defer allocator.free(moons);

    var system = System{ .moons = moons };
    system.simulate(100);

    try std.testing.expectEqual(1940, system.totalEnergy());
}

test "part 2 example 1" {
    const example_input: []const u8 =
        \\<x=-1, y=0, z=2>
        \\<x=2, y=-10, z=-7>
        \\<x=4, y=-8, z=8>
        \\<x=3, y=5, z=-1>
    ;

    const allocator = std.testing.allocator;
    var reader = std.Io.Reader.fixed(example_input);

    const moons = try parseMoons(allocator, &reader);
    defer allocator.free(moons);

    const cycle_period = cyclePeriod(moons);

    try std.testing.expectEqual(2772, cycle_period);
}

test "part 2 example 2" {
    const example_input: []const u8 =
        \\<x=-8, y=-10, z=0>
        \\<x=5, y=5, z=10>
        \\<x=2, y=-7, z=3>
        \\<x=9, y=-8, z=-3>
    ;

    const allocator = std.testing.allocator;
    var reader = std.Io.Reader.fixed(example_input);

    const moons = try parseMoons(allocator, &reader);
    defer allocator.free(moons);

    const cycle_period = cyclePeriod(moons);

    try std.testing.expectEqual(4686774924, cycle_period);
}
