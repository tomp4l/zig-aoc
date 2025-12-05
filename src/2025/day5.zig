const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var ingredients = try Ingredients.parse(allocator, input);
    defer ingredients.deinit(allocator);

    try ingredients.combineRanges(allocator);
    try solution.part1(ingredients.countFreshAvailable());
    try solution.part2(ingredients.countAllFresh());
}

const Range = struct {
    start: usize,
    end: usize,

    fn includes(self: *const @This(), value: usize) bool {
        return value >= self.start and value <= self.end;
    }

    fn tryCombine(self: *const @This(), other: *const @This()) ?Range {
        if (self.end + 1 < other.start or other.end + 1 < self.start) {
            return null;
        }
        return Range{
            .start = @min(self.start, other.start),
            .end = @max(self.end, other.end),
        };
    }

    fn lessThanStart(context: void, a: @This(), b: @This()) bool {
        _ = context;
        return a.start < b.start;
    }

    fn size(self: *const @This()) usize {
        return self.end - self.start + 1;
    }
};

const Ingredients = struct {
    fresh: []Range,
    available: []usize,
    combined: bool = false,

    fn parse(allocator: Allocator, input: *std.Io.Reader) !Ingredients {
        var fresh: std.ArrayList(Range) = .empty;
        var available: std.ArrayList(usize) = .empty;

        while (try input.takeDelimiter('\n')) |line| {
            if (line.len == 0) break;

            var split = std.mem.splitScalar(u8, line, '-');
            const start = try std.fmt.parseInt(usize, split.next() orelse return error.InvalidInput, 10);
            const end = try std.fmt.parseInt(usize, split.next() orelse return error.InvalidInput, 10);

            try fresh.append(allocator, .{ .start = start, .end = end });
        }
        while (try input.takeDelimiter('\n')) |line| {
            if (line.len == 0) break;

            const value = try std.fmt.parseInt(usize, line, 10);
            try available.append(allocator, value);
        }

        return Ingredients{
            .fresh = try fresh.toOwnedSlice(allocator),
            .available = try available.toOwnedSlice(allocator),
        };
    }

    fn countFreshAvailable(self: *const @This()) usize {
        var count: usize = 0;
        for (self.available) |r| {
            for (self.fresh) |f| {
                if (f.includes(r)) {
                    count += 1;
                    break;
                }
            }
        }
        return count;
    }

    fn combineRanges(self: *@This(), allocator: Allocator) !void {
        if (self.fresh.len < 2) return;

        var combined: std.ArrayList(Range) = .empty;

        std.mem.sort(Range, self.fresh, {}, Range.lessThanStart);

        var current = self.fresh[0];
        for (self.fresh[1..]) |next| {
            if (current.tryCombine(&next)) |m| {
                current = m;
            } else {
                try combined.append(allocator, current);
                current = next;
            }
        }
        try combined.append(allocator, current);

        allocator.free(self.fresh);
        self.fresh = try combined.toOwnedSlice(allocator);
        self.combined = true;
    }

    fn countAllFresh(self: *const @This()) usize {
        std.debug.assert(self.combined);
        var count: usize = 0;
        for (self.fresh) |f| {
            count += f.size();
        }
        return count;
    }

    fn deinit(self: Ingredients, allocator: Allocator) void {
        allocator.free(self.fresh);
        allocator.free(self.available);
    }
};

test "example" {
    const example_input: []const u8 =
        \\3-5
        \\10-14
        \\16-20
        \\12-18
        \\
        \\1
        \\5
        \\8
        \\11
        \\17
        \\32
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "3",
        "14",
    );
}
