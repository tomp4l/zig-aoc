const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

const TOTAL_ORE_AVAILABLE: u64 = 1_000_000_000_000;

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var recipes = try Recipes.parse(allocator, input);
    defer recipes.deinit(allocator);

    const ore_for_one_fuel = try recipes.oreToProduceFuel(allocator, 1);
    try solution.part1(ore_for_one_fuel);

    const max_fuel = try findFuelAmountForOre(&recipes, allocator, TOTAL_ORE_AVAILABLE);
    try solution.part2(max_fuel);
}

fn findFuelAmountForOre(
    recipes: *const Recipes,
    allocator: Allocator,
    target_ore: u64,
) !u64 {
    var low: u64 = 1;
    const ore_needed_for_one = try recipes.oreToProduceFuel(allocator, low);
    var high: u64 = target_ore * 2 / ore_needed_for_one;

    while (low < high) {
        const mid = low + (high - low + 1) / 2;
        const ore_needed = try recipes.oreToProduceFuel(allocator, mid);

        if (ore_needed > target_ore) {
            high = mid - 1;
        } else {
            low = mid;
        }
    }

    return low;
}

const Recipe = struct {
    output_amount: u64,
    inputs: std.StringHashMap(u64),

    fn deinit(self: *Recipe) void {
        self.inputs.deinit();
    }
};

const Recipes = struct {
    map: std.StringHashMap(Recipe),
    names: [][]const u8,

    fn getNameOrAllocate(allocator: Allocator, names: *std.StringHashMap(void), name: []const u8) ![]const u8 {
        if (names.getEntry(name)) |e| {
            return e.key_ptr.*;
        } else {
            const name_copy = try allocator.dupe(u8, name);
            _ = try names.put(name_copy, {});
            return name_copy;
        }
    }

    fn parse(allocator: Allocator, input: *std.Io.Reader) !Recipes {
        var map = std.StringHashMap(Recipe).init(allocator);
        var names = std.StringHashMap(void).init(allocator);
        defer names.deinit();

        while (try input.takeDelimiter('\n')) |line| {
            var parts = std.mem.splitSequence(u8, line, " => ");

            var inputs_map = std.StringHashMap(u64).init(allocator);
            const input_part = parts.next() orelse return error.InvalidRecipeLine;
            var input_items = std.mem.splitSequence(u8, input_part, ", ");
            while (input_items.next()) |item| {
                var input_tokens = std.mem.splitScalar(u8, item, ' ');

                const input_amount = try std.fmt.parseInt(u64, input_tokens.next() orelse return error.InvalidRecipeLine, 10);
                const input_name = input_tokens.next() orelse return error.InvalidRecipeLine;
                const input_name_interned = try getNameOrAllocate(allocator, &names, input_name);
                try inputs_map.put(input_name_interned, input_amount);
            }

            const output_part = parts.next() orelse return error.InvalidRecipeLine;
            var output_tokens = std.mem.splitScalar(u8, output_part, ' ');
            const output_amount = try std.fmt.parseInt(u64, output_tokens.next() orelse return error.InvalidRecipeLine, 10);
            const output_name = output_tokens.next() orelse return error.InvalidRecipeLine;
            const output_name_interned = try getNameOrAllocate(allocator, &names, output_name);

            try map.put(output_name_interned, Recipe{
                .output_amount = output_amount,
                .inputs = inputs_map,
            });

            _ = input.peekByte() catch |err| switch (err) {
                error.EndOfStream => continue,
                else => return err,
            };
        }

        const name_slice = try allocator.alloc([]const u8, names.count());

        var name_it = names.keyIterator();
        var idx: usize = 0;
        while (name_it.next()) |name| {
            name_slice[idx] = name.*;
            idx += 1;
        }
        return Recipes{ .map = map, .names = name_slice };
    }

    fn deinit(self: *Recipes, allocator: Allocator) void {
        var it = self.map.valueIterator();
        while (it.next()) |r| {
            r.deinit();
        }
        for (self.names) |name| {
            allocator.free(name);
        }
        allocator.free(self.names);
        self.map.deinit();
    }

    fn oreToProduceFuel(self: *const Recipes, allocator: Allocator, fuel_amount: u64) !u64 {
        const Requirement = struct {
            name: []const u8,
            amount: u64,
        };

        var requirements = try std.ArrayList(Requirement).initCapacity(allocator, self.names.len);
        defer requirements.deinit(allocator);

        var spares = std.StringHashMap(u64).init(allocator);
        defer spares.deinit();

        var ore_needed: u64 = 0;
        try requirements.appendBounded(Requirement{
            .name = "FUEL",
            .amount = fuel_amount,
        });

        while (requirements.pop()) |r| {
            var req = r;

            if (std.mem.eql(u8, req.name, "ORE")) {
                ore_needed += req.amount;
                continue;
            }

            const recipe = self.map.get(req.name) orelse return error.MissingRecipe;
            var spare_amount_entry = try spares.getOrPutValue(req.name, 0);
            const spare_amount = spare_amount_entry.value_ptr;

            if (spare_amount.* >= req.amount) {
                spare_amount.* -= req.amount;
                continue;
            } else if (spare_amount.* > 0) {
                req.amount -= spare_amount.*;
                spare_amount.* = 0;
            }

            // ceiling division
            const times = (req.amount + recipe.output_amount - 1) / recipe.output_amount;

            const produced_amount = times * recipe.output_amount;
            if (produced_amount > req.amount) {
                const new_spare = produced_amount - req.amount;
                spare_amount.* += new_spare;
            }

            var input_it = recipe.inputs.iterator();
            while (input_it.next()) |input_entry| {
                const input_name = input_entry.key_ptr.*;
                const input_amount = input_entry.value_ptr.* * times;
                try requirements.append(allocator, Requirement{
                    .name = input_name,
                    .amount = input_amount,
                });
            }
        }

        return ore_needed;
    }
};

test "example" {
    const example_input: []const u8 =
        \\9 ORE => 2 A
        \\8 ORE => 3 B
        \\7 ORE => 5 C
        \\3 A, 4 B => 1 AB
        \\5 B, 7 C => 1 BC
        \\4 C, 1 A => 1 CA
        \\2 AB, 3 BC, 4 CA => 1 FUEL
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "165",
        null,
    );
}

test "example 2" {
    const example_input: []const u8 =
        \\157 ORE => 5 NZVS
        \\165 ORE => 6 DCFZ
        \\44 XJWVT, 5 KHKGT, 1 QDVJ, 29 NZVS, 9 GPVTF, 48 HKGWZ => 1 FUEL
        \\12 HKGWZ, 1 GPVTF, 8 PSHF => 9 QDVJ
        \\179 ORE => 7 PSHF
        \\177 ORE => 5 HKGWZ
        \\7 DCFZ, 7 PSHF => 2 XJWVT
        \\165 ORE => 2 GPVTF
        \\3 DCFZ, 7 NZVS, 5 HKGWZ, 10 PSHF => 8 KHKGT
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "13312",
        "82892753",
    );
}

test "example 3" {
    const example_input: []const u8 =
        \\171 ORE => 8 CNZTR
        \\7 ZLQW, 3 BMBT, 9 XCVML, 26 XMNCP, 1 WPTQ, 2 MZWV, 1 RJRHP => 4 PLWSL
        \\114 ORE => 4 BHXH
        \\14 VRPVC => 6 BMBT
        \\6 BHXH, 18 KTJDG, 12 WPTQ, 7 PLWSL, 31 FHTLT, 37 ZDVW => 1 FUEL
        \\6 WPTQ, 2 BMBT, 8 ZLQW, 18 KTJDG, 1 XMNCP, 6 MZWV, 1 RJRHP => 6 FHTLT
        \\15 XDBXC, 2 LTCX, 1 VRPVC => 6 ZLQW
        \\13 WPTQ, 10 LTCX, 3 RJRHP, 14 XMNCP, 2 MZWV, 1 ZLQW => 1 ZDVW
        \\5 BMBT => 4 WPTQ
        \\189 ORE => 9 KTJDG
        \\1 MZWV, 17 XDBXC, 3 XCVML => 2 XMNCP
        \\12 VRPVC, 27 CNZTR => 2 XDBXC
        \\15 KTJDG, 12 BHXH => 5 XCVML
        \\3 BHXH, 2 VRPVC => 7 MZWV
        \\121 ORE => 7 VRPVC
        \\7 XCVML => 6 RJRHP
        \\5 BHXH, 4 VRPVC => 5 LTCX
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "2210736",
        "460664",
    );
}
