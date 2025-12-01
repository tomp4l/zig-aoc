const std = @import("std");
const Allocator = std.mem.Allocator;

const parsing = @import("../parsing.zig");

const Self = @This();

pub const int_t = i64;

memory: []int_t,
position: usize = 0,
relative_base: int_t = 0,
input_position: ?int_t = null,
input_mode: u8 = 0,
output_buffer: std.ArrayList(int_t),
last_output_index: usize = 0,
allocator: Allocator,

pub fn parseProgram(allocator: Allocator, input: *std.Io.Reader) ![]int_t {
    return parsing.parseInt(int_t, allocator, input, ',');
}

pub fn init(allocator: Allocator, program: []const int_t) !Self {
    const memory = try allocator.alloc(int_t, program.len);
    @memcpy(memory, program);
    return Self{
        .memory = memory,
        .output_buffer = try std.ArrayList(int_t).initCapacity(allocator, 16),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.memory);
    self.output_buffer.deinit(self.allocator);
}

pub const StepResult = enum {
    Continue,
    RequireInput,
    Halt,
};

fn op3(self: *Self, op: *const fn (int_t, int_t) int_t, m1: u8, m2: u8, m3: u8) !StepResult {
    const param1 = self.memory[self.position + 1];
    const param2 = self.memory[self.position + 2];
    const dest = self.memory[self.position + 3];
    const result = op(try self.memoryAtMode(param1, m1), try self.memoryAtMode(param2, m2));
    try self.setMemoryMode(dest, result, m3);
    self.position += 4;
    return .Continue;
}

fn jumpIf(self: *Self, is_zero: bool, m1: u8, m2: u8) !StepResult {
    const param1 = self.memory[self.position + 1];
    const param2 = self.memory[self.position + 2];
    const value1 = try self.memoryAtMode(param1, m1);
    const value2 = try self.memoryAtMode(param2, m2);
    if (is_zero == (value1 == 0)) {
        self.position = @intCast(value2);
    } else {
        self.position += 3;
    }
    return .Continue;
}

fn add(a: int_t, b: int_t) int_t {
    return a + b;
}

fn multiply(a: int_t, b: int_t) int_t {
    return a * b;
}

fn lessThan(a: int_t, b: int_t) int_t {
    return @intFromBool(a < b);
}

fn equals(a: int_t, b: int_t) int_t {
    return @intFromBool(a == b);
}

fn step(self: *Self) !StepResult {
    if (self.input_position != null) {
        return error.InputRequested;
    }

    const instruction = self.memory[self.position];
    const op = @mod(instruction, 100);
    const m1 = @as(u8, @intCast(@mod(@divTrunc(instruction, 100), 10)));
    const m2 = @as(u8, @intCast(@mod(@divTrunc(instruction, 1000), 10)));
    const m3 = @as(u8, @intCast(@mod(@divTrunc(instruction, 10000), 10)));

    switch (op) {
        1 => return self.op3(add, m1, m2, m3),
        2 => return self.op3(multiply, m1, m2, m3),
        3 => {
            const dest = self.memory[self.position + 1];
            self.input_position = @intCast(dest);
            self.input_mode = m1;
            self.position += 2;
            return .RequireInput;
        },
        4 => {
            const param1 = self.memory[self.position + 1];
            const value = try self.memoryAtMode(param1, m1);
            try self.output_buffer.append(self.allocator, value);
            self.position += 2;
            return .Continue;
        },
        5 => return self.jumpIf(false, m1, m2),
        6 => return self.jumpIf(true, m1, m2),
        7 => return self.op3(lessThan, m1, m2, m3),
        8 => return self.op3(equals, m1, m2, m3),
        9 => {
            const param1 = self.memory[self.position + 1];
            const value = try self.memoryAtMode(@intCast(param1), m1);
            self.relative_base += value;
            self.position += 2;
            return .Continue;
        },
        99 => return .Halt,
        else => return error.InvalidOpcode,
    }
}

pub fn run(self: *Self) !bool {
    while (true) {
        switch (try self.step()) {
            .Continue => {},
            .Halt => return true,
            .RequireInput => return false,
        }
    }
}

pub fn provideInput(self: *Self, input: int_t) !void {
    if (self.input_position == null) {
        return error.NoInputRequested;
    }
    try self.setMemoryMode(self.input_position.?, input, self.input_mode);
    self.input_position = null;
}

pub fn provideInputAndRun(self: *Self, input: int_t) !bool {
    try self.provideInput(input);
    return self.run();
}

pub fn getLastOutput(self: *Self) int_t {
    return self.getPreviousOutput(0);
}

pub fn getPreviousOutput(self: *Self, index: usize) int_t {
    return self.output_buffer.items[self.output_buffer.items.len - 1 - index];
}

pub fn getNextOutput(self: *Self) ?int_t {
    if (self.last_output_index >= self.output_buffer.items.len) {
        return null;
    }
    const value = self.output_buffer.items[self.last_output_index];
    self.last_output_index += 1;
    if (self.last_output_index == self.output_buffer.items.len) {
        self.last_output_index = 0;
        self.output_buffer.clearRetainingCapacity();
    }
    return value;
}

pub fn memoryAt(self: *Self, address: usize) int_t {
    if (address >= self.memory.len) {
        return 0;
    }
    return self.memory[address];
}

fn memoryAtMode(self: *Self, address: int_t, mode: u8) !int_t {
    switch (mode) {
        0 => return self.memoryAt(@intCast(address)),
        1 => return address,
        2 => {
            const dest = self.relative_base + @as(int_t, @intCast(address));
            return self.memoryAt(@intCast(dest));
        },
        else => return error.InvalidParameterMode,
    }
}

pub fn setMemory(self: *Self, address: usize, value: int_t) !void {
    if (address >= self.memory.len) {
        const old_length = self.memory.len;
        const new_size = address + address / 2 + 1;
        if (self.allocator.remap(self.memory, new_size)) |new_memory| {
            self.memory = new_memory;
        } else {
            const new_memory = try self.allocator.alloc(int_t, new_size);
            @memcpy(new_memory[0..self.memory.len], self.memory);
            self.allocator.free(self.memory);
            self.memory = new_memory;
        }
        @memset(self.memory[old_length..], 0);
    }
    self.memory[address] = value;
}

fn setMemoryMode(self: *Self, address: int_t, value: int_t, mode: u8) !void {
    switch (mode) {
        0 => try self.setMemory(@intCast(address), value),
        2 => {
            const dest = self.relative_base + address;
            try self.setMemory(@intCast(dest), value);
        },
        else => return error.InvalidParameterMode,
    }
}

test "simple program" {
    const allocator = std.testing.allocator;
    const program: []const int_t = &[_]int_t{ 1, 0, 0, 0, 99 };
    var intcode = try Self.init(allocator, program);
    defer intcode.deinit();

    _ = try intcode.run();

    try std.testing.expect(intcode.memory[0] == 2);
}

test "immediate mode" {
    const allocator = std.testing.allocator;
    const program: []const int_t = &[_]int_t{ 1002, 4, 3, 0, 99 };
    var intcode = try Self.init(allocator, program);
    defer intcode.deinit();

    _ = try intcode.run();

    try std.testing.expectEqual(99 * 3, intcode.memoryAt(0));
}

test "input / output" {
    const allocator = std.testing.allocator;
    const program: []const int_t = &[_]int_t{ 3, 0, 4, 0, 99 };
    var intcode = try Self.init(allocator, program);
    defer intcode.deinit();

    const not_finished = try intcode.run();
    try std.testing.expect(!not_finished);
    const finished = try intcode.provideInputAndRun(42);
    try std.testing.expect(finished);

    try std.testing.expectEqual(42, intcode.getLastOutput());
}

test "conditionals" {
    const TestCase = struct {
        program: []const int_t,
        input: int_t,
        expected_output: int_t,
    };

    const compare_to_8_program: []const int_t = &[_]int_t{
        3,    21,   1008, 21, 8,    20,   1005, 20, 22,  107, 8,    21, 20,   1006, 20, 31, //long program...
        1106, 0,    36,   98, 0,    0,    1002, 21, 125, 20,  4,    20, 1105, 1,    46, 104,
        999,  1105, 1,    46, 1101, 1000, 1,    20, 4,   20,  1105, 1,  46,   98,   99,
    };

    const test_cases = [_]TestCase{
        .{ .program = &[_]int_t{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 }, .input = 8, .expected_output = 1 },
        .{ .program = &[_]int_t{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 }, .input = 7, .expected_output = 0 },
        .{ .program = &[_]int_t{ 3, 3, 1108, -1, 8, 3, 4, 3, 99 }, .input = 8, .expected_output = 1 },
        .{ .program = &[_]int_t{ 3, 3, 1108, -1, 8, 3, 4, 3, 99 }, .input = 9, .expected_output = 0 },
        .{ .program = &[_]int_t{ 3, 12, 6, 12, 15, 1, 13, 14, 13, 4, 13, 99, -1, 0, 1, 9 }, .input = 0, .expected_output = 0 },
        .{ .program = &[_]int_t{ 3, 12, 6, 12, 15, 1, 13, 14, 13, 4, 13, 99, -1, 0, 1, 9 }, .input = 5, .expected_output = 1 },
        .{ .program = &[_]int_t{ 3, 3, 1105, -1, 9, 1101, 0, 0, 12, 4, 12, 99, 1 }, .input = 0, .expected_output = 0 },
        .{ .program = &[_]int_t{ 3, 3, 1105, -1, 9, 1101, 0, 0, 12, 4, 12, 99, 1 }, .input = 5, .expected_output = 1 },
        .{ .program = compare_to_8_program, .input = 7, .expected_output = 999 },
        .{ .program = compare_to_8_program, .input = 8, .expected_output = 1000 },
        .{ .program = compare_to_8_program, .input = 9, .expected_output = 1001 },
    };

    const allocator = std.testing.allocator;
    for (test_cases) |test_case| {
        var intcode = try Self.init(allocator, test_case.program);
        defer intcode.deinit();

        const not_finished = try intcode.run();
        try std.testing.expect(!not_finished);
        const finished = try intcode.provideInputAndRun(test_case.input);
        try std.testing.expect(finished);

        try std.testing.expectEqual(test_case.expected_output, intcode.getLastOutput());
    }
}

test "quine output" {
    const allocator = std.testing.allocator;
    const program: []const int_t = &[_]int_t{ 109, 1, 204, -1, 1001, 100, 1, 100, 1008, 100, 16, 101, 1006, 101, 0, 99 };
    var intcode = try Self.init(allocator, program);
    defer intcode.deinit();

    _ = try intcode.run();

    try std.testing.expect(intcode.output_buffer.items.len == program.len);
    for (program, 0..) |value, index| {
        try std.testing.expectEqual(value, intcode.output_buffer.items[index]);
    }
}

test "big output" {
    const allocator = std.testing.allocator;
    const program: []const int_t = &[_]int_t{ 1102, 34915192, 34915192, 7, 4, 7, 99, 0 };
    var intcode = try Self.init(allocator, program);
    defer intcode.deinit();

    _ = try intcode.run();

    const output = intcode.getLastOutput();
    var digit_count: usize = 0;
    var temp = output;
    while (temp != 0) : (digit_count += 1) {
        temp = @divTrunc(temp, 10);
    }
    try std.testing.expect(digit_count == 16);
}
