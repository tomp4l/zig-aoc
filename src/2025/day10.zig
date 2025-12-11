const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const machines = try parsing.parseAny(allocator, Machine.parse, input, '\n');
    defer {
        for (machines) |machine| {
            machine.deinit(allocator);
        }
        allocator.free(machines);
    }

    var total_button_presses: usize = 0;
    var total_button_presses_joltage: usize = 0;
    for (machines) |machine| {
        total_button_presses += try machine.buttonPressesNeeded(allocator);
        total_button_presses_joltage += try machine.buttonPressesNeededJoltage(allocator);
    }

    try solution.part1(total_button_presses);
    try solution.part2(total_button_presses_joltage);
}

const Machine = struct {
    lights: []bool,
    buttons: [][]u8,
    joltage: []u16,

    fn parse(allocator: Allocator, input: []const u8) !Machine {
        var lights: std.ArrayList(bool) = .empty;
        var buttons: std.ArrayList([]u8) = .empty;
        var joltage: std.ArrayList(u16) = .empty;

        errdefer {
            for (buttons.items) |btn| {
                allocator.free(btn);
            }
            lights.deinit(allocator);
            buttons.deinit(allocator);
            joltage.deinit(allocator);
        }

        var tokens = std.mem.tokenizeScalar(u8, input, ' ');

        while (tokens.next()) |token| {
            var sub_tokens = std.mem.tokenizeAny(u8, token, ",(){}");
            switch (token[0]) {
                '[' => {
                    for (token[1 .. token.len - 1]) |char| {
                        if (char == '#') {
                            try lights.append(allocator, true);
                        } else if (char == '.') {
                            try lights.append(allocator, false);
                        } else {
                            return error.UnexpectedToken;
                        }
                    }
                },
                '(' => {
                    var button_cfg = try std.ArrayList(u8).initCapacity(allocator, lights.items.len);
                    while (sub_tokens.next()) |btn_token| {
                        const parsed = try std.fmt.parseInt(u8, btn_token, 10);
                        try button_cfg.appendBounded(parsed);
                    }
                    try buttons.append(allocator, try button_cfg.toOwnedSlice(allocator));
                },
                '{' => {
                    try joltage.ensureTotalCapacity(allocator, lights.items.len);
                    while (sub_tokens.next()) |joltage_token| {
                        const parsed = try std.fmt.parseInt(u16, joltage_token, 10);
                        try joltage.appendBounded(parsed);
                    }
                },
                else => return error.UnexpectedToken,
            }
        }

        return Machine{
            .lights = try lights.toOwnedSlice(allocator),
            .buttons = try buttons.toOwnedSlice(allocator),
            .joltage = try joltage.toOwnedSlice(allocator),
        };
    }

    const ToggleState = struct {
        machine: ToggleMachine,
        steps: usize,
        node: std.DoublyLinkedList.Node = .{},

        fn isSolved(self: @This()) bool {
            return self.machine.state == self.machine.target_state;
        }
    };

    fn buttonPressesNeeded(self: Machine, allocator: Allocator) !usize {
        var toggle_machine = try ToggleMachine.init(allocator, self);
        defer toggle_machine.deinit(allocator);

        const initial_state = try allocator.create(ToggleState);
        initial_state.* = .{
            .machine = toggle_machine,
            .steps = 0,
        };

        var states: std.DoublyLinkedList = .{};
        defer {
            while (states.pop()) |state_node| {
                const state: *ToggleState = @fieldParentPtr("node", state_node);
                allocator.destroy(state);
            }
        }
        states.append(&initial_state.node);

        var visited_states = std.AutoHashMap(usize, void).init(allocator);
        defer visited_states.deinit();
        try visited_states.put(initial_state.machine.state, {});

        while (states.popFirst()) |state_node| {
            const state: *ToggleState = @fieldParentPtr("node", state_node);
            defer allocator.destroy(state);

            if (state.isSolved()) {
                return state.steps;
            }

            for (0..state.machine.buttons.len) |btn_idx| {
                var new_machine = state.machine;
                new_machine.applyButton(btn_idx);

                if (visited_states.contains(new_machine.state)) continue;
                try visited_states.put(new_machine.state, {});

                const new_state = try allocator.create(ToggleState);
                new_state.* = .{
                    .machine = new_machine,
                    .steps = state.steps + 1,
                };
                states.append(&new_state.node);
            }
        }
        unreachable;
    }

    const SEARCH_RANGE = 10;
    fn buttonPressesNeededJoltage(self: Machine, allocator: Allocator) !usize {
        var simplex = try Simplex.init(allocator, self);
        defer simplex.deinit(allocator);
        const initial_result = try simplex.solve(allocator);
        defer initial_result.deinit(allocator);
        const lower_bound: u16 = @intFromFloat(initial_result.total_presses);

        var min: usize = std.math.maxInt(usize);
        outer_outer: for (0..self.buttons.len) |i| {
            const start: usize = @intFromFloat(initial_result.button_presses[i]);
            outer: for (start..start + SEARCH_RANGE) |peturb| {
                const change: u16 = @intCast(peturb);
                const new_joltage = try allocator.alloc(u16, self.joltage.len);
                @memcpy(new_joltage, self.joltage);
                for (self.buttons[i]) |btn_idx| {
                    if (new_joltage[btn_idx] < change) {
                        allocator.free(new_joltage);
                        continue :outer_outer;
                    }
                    new_joltage[btn_idx] -= change;
                }
                defer allocator.free(new_joltage);

                const new_machine: Machine = .{
                    .lights = self.lights,
                    .buttons = self.buttons,
                    .joltage = new_joltage,
                };
                var new_simplex = try Simplex.init(allocator, new_machine);
                defer new_simplex.deinit(allocator);
                const new_result = try new_simplex.solve(allocator);
                defer new_result.deinit(allocator);
                var new_total_presses = change;

                for (new_result.button_presses, 0..) |cnt, j| {
                    const presses: u16 = @intFromFloat(std.math.round(cnt));
                    new_total_presses += presses;
                    for (self.buttons[j]) |btn_idx| {
                        if (new_joltage[btn_idx] >= presses) {
                            new_joltage[btn_idx] -= presses;
                        } else {
                            continue :outer;
                        }
                    }
                }

                var all_zero = true;
                for (new_joltage) |joltage| {
                    if (joltage != 0) {
                        all_zero = false;
                        break;
                    }
                }
                if (all_zero) {
                    min = @min(min, new_total_presses);
                    if (min == lower_bound) {
                        return min;
                    }
                }
            }
        }
        if (min == std.math.maxInt(usize)) {
            return error.NoSolution;
        }
        return min;
    }

    pub fn deinit(self: Machine, allocator: Allocator) void {
        for (self.buttons) |btn| {
            allocator.free(btn);
        }
        allocator.free(self.buttons);
        allocator.free(self.joltage);
        allocator.free(self.lights);
    }
};

const ToggleMachine = struct {
    target_state: usize,
    state: usize,
    buttons: []usize,

    fn init(allocator: Allocator, machine: Machine) !@This() {
        var buttons: std.ArrayList(usize) = .empty;
        defer buttons.deinit(allocator);

        for (machine.buttons) |btn_cfg| {
            var btn_value: usize = 0;
            for (btn_cfg) |idx| {
                btn_value |= @as(usize, 1) << @intCast(idx);
            }
            try buttons.append(allocator, btn_value);
        }

        var state: usize = 0;
        for (machine.lights, 0..) |light, idx| {
            if (light) {
                state |= @as(usize, 1) << @intCast(idx);
            }
        }

        return .{
            .target_state = state,
            .state = 0,
            .buttons = try buttons.toOwnedSlice(allocator),
        };
    }

    fn applyButton(self: *@This(), button_idx: usize) void {
        self.state ^= self.buttons[button_idx];
    }

    fn deinit(self: ToggleMachine, allocator: Allocator) void {
        allocator.free(self.buttons);
    }
};

const Matrix = struct {
    matrix: [][]f64,

    fn fromConst(allocator: Allocator, input: []const []const f64) !@This() {
        var rows: std.ArrayList([]f64) = .empty;
        defer rows.deinit(allocator);

        for (input) |row| {
            const new_row = try allocator.alloc(f64, row.len);
            @memcpy(new_row, row);
            try rows.append(allocator, new_row);
        }

        return Matrix{
            .matrix = try rows.toOwnedSlice(allocator),
        };
    }

    fn width(self: *const @This()) usize {
        return self.matrix[0].len;
    }

    fn height(self: *const @This()) usize {
        return self.matrix.len;
    }

    fn debugPrint(self: *const @This()) void {
        for (self.matrix) |row| {
            for (row, 0..) |value, i| {
                if (i != 0) {
                    std.debug.print(" ", .{});
                }
                if (value < 0.0) {
                    std.debug.print("{:.1}", .{value});
                } else {
                    std.debug.print("{:.2}", .{value});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    fn deinit(self: Matrix, allocator: Allocator) void {
        for (self.matrix) |row| {
            allocator.free(row);
        }
        allocator.free(self.matrix);
    }
};

fn runSimplex(tableau: *Matrix) !void {
    while (true) {
        var entering_col: ?usize = null;
        for (0..tableau.width() - 1) |j| {
            if (tableau.matrix[tableau.height() - 1][j] < 0.0) {
                entering_col = j;
                break;
            }
        }
        if (entering_col == null) break;

        var min_ratio: ?f64 = null;
        var leaving_row: ?usize = null;
        for (0..tableau.height() - 1) |i| {
            const coeff = tableau.matrix[i][entering_col.?];
            if (coeff > 0.0) {
                const ratio = tableau.matrix[i][tableau.width() - 1] / coeff;
                if (min_ratio == null or ratio < min_ratio.?) {
                    min_ratio = ratio;
                    leaving_row = i;
                }
            }
        }
        if (leaving_row == null) return error.Unbounded;

        const pivot = tableau.matrix[leaving_row.?][entering_col.?];
        for (0..tableau.width()) |j| {
            tableau.matrix[leaving_row.?][j] /= pivot;
        }
        for (0..tableau.height()) |i| {
            if (i != leaving_row.?) {
                const factor = tableau.matrix[i][entering_col.?];
                for (0..tableau.width()) |j| {
                    tableau.matrix[i][j] -= factor * tableau.matrix[leaving_row.?][j];
                }
            }
        }
    }
}

fn phase1(allocator: Allocator, matrix: Matrix) !Matrix {
    const col_len = matrix.height();
    const row_len = matrix.width();
    const tableau = matrix.matrix;

    var new_tableau = try allocator.alloc([]f64, col_len + 1);

    for (0..tableau.len) |i| {
        new_tableau[i] = try allocator.alloc(f64, row_len + col_len);
        @memset(new_tableau[i], 0.0);

        @memcpy(new_tableau[i][0 .. row_len - 1], tableau[i][0 .. row_len - 1]);
        new_tableau[i][row_len - 1 + i] = 1.0;

        new_tableau[i][row_len + col_len - 1] = tableau[i][row_len - 1];
    }
    new_tableau[col_len] = try allocator.alloc(f64, row_len + col_len);
    @memset(new_tableau[col_len], 0.0);
    for (0..col_len) |i| {
        for (0..new_tableau[0].len) |j| {
            new_tableau[col_len][j] -= new_tableau[i][j];
        }
    }
    for (row_len - 1..new_tableau[0].len - 1) |j| {
        new_tableau[col_len][j] = 0.0;
    }

    var new_matrix = Matrix{ .matrix = new_tableau };

    try runSimplex(&new_matrix);

    return new_matrix;
}

const Simplex = struct {
    constraints: Matrix,
    equation: []const f64,

    fn init(allocator: Allocator, machine: Machine) !@This() {
        const equation = try allocator.alloc(f64, machine.buttons.len);
        @memset(equation, 1);

        const num_constraints = machine.joltage.len;
        var constraint_rows = try allocator.alloc([]f64, num_constraints);
        errdefer {
            for (constraint_rows) |row| {
                allocator.free(row);
            }
            allocator.free(constraint_rows);
        }

        for (machine.joltage, 0..) |joltage, i| {
            constraint_rows[i] = try allocator.alloc(f64, machine.buttons.len + 1);
            @memset(constraint_rows[i], 0.0);
            constraint_rows[i][machine.buttons.len] = @floatFromInt(joltage);
        }

        for (machine.buttons, 0..) |btn_cfg, j| {
            for (btn_cfg) |i| {
                constraint_rows[i][j] = 1.0;
            }
        }

        const constraints = Matrix{ .matrix = constraint_rows };

        return .{
            .constraints = constraints,
            .equation = equation,
        };
    }

    const Result = struct {
        button_presses: []f64,
        total_presses: f64,

        fn deinit(self: Result, allocator: Allocator) void {
            allocator.free(self.button_presses);
        }
    };

    fn solve(self: *@This(), allocator: Allocator) !Result {
        const tableau = try phase1(allocator, self.constraints);
        defer tableau.deinit(allocator);

        const num_vars = self.constraints.width() - 1;
        const num_constraints = self.constraints.height();

        for (0..num_constraints) |i| {
            @memcpy(self.constraints.matrix[i][0..num_vars], tableau.matrix[i][0..num_vars]);
            self.constraints.matrix[i][num_vars] = tableau.matrix[i][tableau.width() - 1];
        }

        var basis_vars = try allocator.alloc(?usize, num_constraints);
        defer allocator.free(basis_vars);
        for (0..num_constraints) |i| {
            basis_vars[i] = null;
            for (0..num_vars) |j| {
                if (std.math.approxEqAbs(f64, self.constraints.matrix[i][j], 1.0, 1e-9)) {
                    var is_basis = true;
                    for (0..num_constraints) |k| {
                        if (k != i and self.constraints.matrix[k][j] != 0.0) {
                            is_basis = false;
                            break;
                        }
                    }
                    if (is_basis) {
                        basis_vars[i] = j;
                        break;
                    }
                }
            }
        }

        var cost_row = try allocator.alloc(f64, num_vars + 1);
        @memcpy(cost_row[0..num_vars], self.equation);
        cost_row[num_vars] = 0.0;
        for (basis_vars, 0..) |maybe_col, row| {
            if (maybe_col == null) continue;
            const col = maybe_col.?;
            const factor = cost_row[col];
            for (0..num_vars + 1) |j| {
                cost_row[j] -= factor * self.constraints.matrix[row][j];
            }
        }

        const new_tableau = try allocator.alloc([]f64, num_constraints + 1);
        for (0..num_constraints) |i| {
            new_tableau[i] = try allocator.alloc(f64, num_vars + 1);
            @memcpy(new_tableau[i], self.constraints.matrix[i]);
        }
        new_tableau[num_constraints] = cost_row;
        var tableau_matrix = Matrix{ .matrix = new_tableau };
        defer tableau_matrix.deinit(allocator);

        try runSimplex(&tableau_matrix);

        for (0..num_constraints) |i| {
            basis_vars[i] = null;
            for (0..num_vars) |j| {
                if (std.math.approxEqAbs(f64, tableau_matrix.matrix[i][j], 1.0, 1e-9)) {
                    var is_basis = true;
                    for (0..num_constraints) |k| {
                        if (k != i and tableau_matrix.matrix[k][j] != 0.0) {
                            is_basis = false;
                            break;
                        }
                    }
                    if (is_basis) {
                        basis_vars[i] = j;
                        break;
                    }
                }
            }
        }

        var total: f64 = 0.0;
        const button_presses = try allocator.alloc(f64, num_vars);
        @memset(button_presses, 0.0);
        for (basis_vars, 0..) |maybe_col, row| {
            if (maybe_col == null) continue;
            const col = maybe_col.?;
            total += tableau_matrix.matrix[row][num_vars];
            button_presses[col] = tableau_matrix.matrix[row][num_vars];
        }
        return .{
            .button_presses = button_presses,
            .total_presses = total,
        };
    }

    fn deinit(self: Simplex, allocator: Allocator) void {
        self.constraints.deinit(allocator);
        allocator.free(self.equation);
    }
};

test "example" {
    const example_input: []const u8 =
        \\[.##.] (3) (1,3) (2) (2,3) (0,2) (0,1) {3,5,4,7}
        \\[...#.] (0,2,3,4) (2,3) (0,4) (0,1,2) (1,2,3,4) {7,5,12,7,2}
        \\[.###.#] (0,1,2,3,4) (0,3,4) (0,1,2,4,5) (1,2) {10,11,11,5,10,5}
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "7",
        "33",
    );
}

test "simplex" {
    const allocator = std.testing.allocator;

    const tableau: [4][]const f64 = .{
        &.{ 0, 0, 0, 0, 1, 1, 3 },
        &.{ 0, 1, 0, 0, 0, 1, 5 },
        &.{ 0, 0, 1, 1, 1, 0, 4 },
        &.{ 1, 1, 0, 1, 0, 0, 7 },
    };

    const matrix = try Matrix.fromConst(allocator, &tableau);
    const equation = try allocator.alloc(f64, 6);
    @memset(equation, 1);
    var simplex: Simplex = .{
        .constraints = matrix,
        .equation = equation,
    };
    defer simplex.deinit(allocator);
    const total = try simplex.solve(allocator);
    defer total.deinit(allocator);

    try std.testing.expectEqual(10.0, total.total_presses);
}

test "harder example" {
    const example_input: []const u8 =
        \\[.#.#] (0,2,3) (1,3) (2) (1,2) (0,1) {19,31,29,12}
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "1",
        "42",
    );
}

test "even harder example" {
    const example_input: []const u8 =
        \\[.#...##.#.] (1,2,4,5,7) (7,9) (0,1,2,3,4,6) (0,1,3,6,8,9) (2,3,6) (0,4,5,8,9) (7) (1,5,6,8) (0,1,2,3,4,6,7,8) (0,2,4,5,7,9) (0,8) (0,1,3,5,6,7,8,9) (3,7) {65,62,54,47,51,64,64,62,76,35}
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "1",
        "122",
    );
}
