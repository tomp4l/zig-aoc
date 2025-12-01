const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const input_data = try input.allocRemaining(allocator, .unlimited);
    defer allocator.free(input_data);
    const objects = try parse(allocator, input_data);
    defer allocator.free(objects);

    var system = try System.init(allocator, objects);
    defer system.deinit(allocator);

    try solution.part1(system.totalOrbits());
    try solution.part2(try system.traverse(allocator, "YOU", "SAN"));
}

const Object = struct {
    name: []const u8,
    parent: []const u8,
};

fn parse(allocator: Allocator, input: []const u8) ![]Object {
    var objects = try std.ArrayList(Object).initCapacity(allocator, input.len / 7);

    var iter = std.mem.tokenizeScalar(u8, input, '\n');

    while (iter.next()) |line| {
        var parts = std.mem.splitScalar(u8, line, ')');
        const parent = parts.next() orelse
            return error.InvalidInput;
        const child = parts.next() orelse
            return error.InvalidInput;

        try objects.append(allocator, Object{
            .name = child,
            .parent = parent,
        });
    }

    return objects.toOwnedSlice(allocator);
}

const System = struct {
    orbits: std.StringHashMap(std.ArrayList([]const u8)),
    links: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, objects: []Object) !System {
        var orbits = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
        var links = std.StringHashMap([]const u8).init(allocator);

        for (objects) |obj| {
            const entry = try orbits.getOrPut(obj.parent);
            if (!entry.found_existing) {
                entry.value_ptr.* = try std.ArrayList([]const u8).initCapacity(allocator, 4);
            }

            try entry.value_ptr.append(allocator, obj.name);

            try links.put(obj.name, obj.parent);
        }

        return System{
            .links = links,
            .orbits = orbits,
        };
    }

    pub fn deinit(self: *System, allocator: Allocator) void {
        var it = self.orbits.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.orbits.deinit();
        self.links.deinit();
    }

    fn countOrbits(self: *System, object: []const u8, depth: usize) usize {
        var total = depth;
        const children_entry = self.orbits.get(object);
        if (children_entry) |children| {
            for (children.items) |child| {
                total += self.countOrbits(child, depth + 1);
            }
        }
        return total;
    }

    fn totalOrbits(self: *System) usize {
        return self.countOrbits("COM", 0);
    }

    fn traverse(self: *System, allocator: Allocator, start: []const u8, end: []const u8) !usize {
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();

        const QueueEntry = struct {
            name: []const u8,
            depth: usize,
            node: std.DoublyLinkedList.Node = .{},
        };

        var queue = std.DoublyLinkedList{};
        defer while (queue.len() > 0) {
            const node = queue.popFirst() orelse break;
            const entry: *QueueEntry = @fieldParentPtr("node", node);
            allocator.destroy(entry);
        };

        const first = try allocator.create(QueueEntry);
        first.* = .{ .name = start, .depth = 0 };
        queue.append(&first.node);

        while (queue.len() > 0) {
            const current_node = queue.popFirst() orelse unreachable;
            const current: *QueueEntry = @fieldParentPtr("node", current_node);
            defer allocator.destroy(current);

            if (std.mem.eql(u8, current.name, end)) {
                return current.depth - 2;
            }

            if (visited.contains(current.name)) {
                continue;
            }
            _ = try visited.put(current.name, {});

            const parent_entry = self.links.get(current.name);
            if (parent_entry) |parent| {
                const next = try allocator.create(QueueEntry);
                next.* = .{ .name = parent, .depth = current.depth + 1 };
                queue.append(&next.node);
            }

            const children_entry = self.orbits.get(current.name);
            if (children_entry) |children| {
                for (children.items) |child| {
                    const next = try allocator.create(QueueEntry);
                    next.* = .{ .name = child, .depth = current.depth + 1 };
                    queue.append(&next.node);
                }
            }
        }

        return error.NoPathFound;
    }
};

test "example" {
    const example_input: []const u8 =
        \\COM)B
        \\B)C
        \\C)D
        \\D)E
        \\E)F
        \\B)G
        \\G)H
        \\D)I
        \\E)J
        \\J)K
        \\K)L
        \\K)YOU
        \\I)SAN
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "54",
        "4",
    );
}
