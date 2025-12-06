const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const lines = try Lines.parse(allocator, input);
    defer lines.deinit(allocator);

    const tabulated = try Tabulated.parse(allocator, &lines);
    defer tabulated.deinit(allocator);
    try solution.part1(tabulated.calculate());

    const cephalopod_tabulated = try CephalopodTabulated.parse(allocator, &lines);
    defer cephalopod_tabulated.deinit(allocator);
    try solution.part2(cephalopod_tabulated.calculate());
}

const Lines = struct {
    lines: [][]const u8,

    fn parse(allocator: Allocator, input: *std.Io.Reader) !Lines {
        var lines: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (lines.items) |line| {
                allocator.free(line);
            }
            lines.deinit(allocator);
        }
        while (true) {
            var line = std.Io.Writer.Allocating.init(allocator);
            defer line.deinit();
            const line_length = try input.streamDelimiterEnding(&line.writer, '\n');
            if (line_length == 0) break;

            const owned_slice = try line.toOwnedSlice();
            errdefer allocator.free(owned_slice);
            try lines.append(allocator, owned_slice);

            input.discardAll(1) catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
        }

        return Lines{
            .lines = try lines.toOwnedSlice(allocator),
        };
    }

    fn deinit(self: *const @This(), allocator: Allocator) void {
        for (self.lines) |line| {
            allocator.free(line);
        }
        allocator.free(self.lines);
    }
};

const Operand = enum {
    add,
    multiply,
};

const Tabulated = struct {
    table: [][]usize,
    operands: []Operand,

    fn parse(allocator: Allocator, input: *const Lines) !Tabulated {
        var operands: std.ArrayList(Operand) = .empty;
        var table: std.ArrayList([]usize) = .empty;
        errdefer {
            operands.deinit(allocator);
            for (table.items) |row| {
                allocator.free(row);
            }
            table.deinit(allocator);
        }
        for (input.lines) |line| {
            var tokens = std.mem.tokenizeScalar(u8, line, ' ');
            var result: ?std.ArrayList(usize) = null;
            while (tokens.next()) |token| {
                if (std.mem.eql(u8, token, "*")) {
                    try operands.append(allocator, .multiply);
                } else if (std.mem.eql(u8, token, "+")) {
                    try operands.append(allocator, .add);
                } else {
                    const value = try std.fmt.parseInt(usize, token, 10);
                    if (result == null) {
                        result = .empty;
                    }
                    try result.?.append(allocator, value);
                }
            }
            if (result) |*row_values| {
                const owned_row = try row_values.toOwnedSlice(allocator);
                errdefer allocator.free(owned_row);
                try table.append(allocator, owned_row);
            }
        }

        if (table.items.len == 0) return error.EmptyTable;
        const first_row_len = table.items[0].len;
        for (table.items) |row| {
            if (row.len != first_row_len)
                return error.InconsistentRowLengths;
        }
        if (operands.items.len != first_row_len)
            return error.OperandCountMismatch;

        return Tabulated{
            .table = try table.toOwnedSlice(allocator),
            .operands = try operands.toOwnedSlice(allocator),
        };
    }

    fn deinit(self: *const @This(), allocator: Allocator) void {
        for (self.table) |row| {
            allocator.free(row);
        }
        allocator.free(self.table);
        allocator.free(self.operands);
    }

    fn calculate(self: *const @This()) usize {
        var result: usize = 0;

        for (self.operands, 0..) |operand, i| {
            var value: usize = switch (operand) {
                .add => 0,
                .multiply => 1,
            };
            for (self.table) |row| {
                switch (operand) {
                    .add => value += row[i],
                    .multiply => value *= row[i],
                }
            }
            result += value;
        }
        return result;
    }
};

const CephalopodTabulated = struct {
    const Calculation = struct {
        numbers: []usize,
        operand: Operand,

        fn deinit(self: *const @This(), allocator: Allocator) void {
            allocator.free(self.numbers);
        }

        fn calculate(self: *const @This()) usize {
            var value: usize = switch (self.operand) {
                .add => 0,
                .multiply => 1,
            };
            for (self.numbers) |num| {
                switch (self.operand) {
                    .add => value += num,
                    .multiply => value *= num,
                }
            }
            return value;
        }
    };

    calculations: []Calculation,

    fn parse(allocator: Allocator, input: *const Lines) !@This() {
        var calculations: std.ArrayList(Calculation) = .empty;
        errdefer {
            for (calculations.items) |calc| {
                calc.deinit(allocator);
            }
            calculations.deinit(allocator);
        }
        var current_operand: ?Operand = null;
        var current_numbers: std.ArrayList(usize) = .empty;
        errdefer current_numbers.deinit(allocator);

        if (input.lines.len < 2) return error.InvalidInputLength;
        for (0..input.lines[0].len) |i| {
            var number: ?usize = null;
            // Read column vertically, building multi-digit numbers from rows
            for (input.lines) |line| {
                if (i >= line.len) return error.InconsistentRowLengths;
                const c = line[i];
                if (c == '*') {
                    current_operand = .multiply;
                } else if (c == '+') {
                    current_operand = .add;
                } else if (c >= '0' and c <= '9') {
                    number = (number orelse 0) * 10 + c - '0';
                }
            }

            if (number) |n| {
                try current_numbers.append(allocator, n);
            } else {
                if (current_operand) |op| {
                    try calculations.append(allocator, Calculation{
                        .numbers = try current_numbers.toOwnedSlice(allocator),
                        .operand = op,
                    });
                    current_operand = null;
                } else {
                    return error.InvalidInputCharacter;
                }
            }
        }

        if (current_operand) |op| {
            try calculations.append(allocator, Calculation{
                .numbers = try current_numbers.toOwnedSlice(allocator),
                .operand = op,
            });
        } else {
            return error.InvalidInputCharacter;
        }

        return .{
            .calculations = try calculations.toOwnedSlice(allocator),
        };
    }

    fn calculate(self: *const @This()) usize {
        var result: usize = 0;

        for (self.calculations) |calc| {
            result += calc.calculate();
        }

        return result;
    }

    fn deinit(self: *const @This(), allocator: Allocator) void {
        for (self.calculations) |calc| {
            calc.deinit(allocator);
        }
        allocator.free(self.calculations);
    }
};

test "example" {
    const example_input: []const u8 =
        \\123 328  51 64 
        \\ 45 64  387 23 
        \\  6 98  215 314
        \\*   +   *   +  
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "4277556",
        "3263827",
    );
}
