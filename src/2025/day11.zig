const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");

pub fn run(allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    var rack = try ServerRack.parse(allocator, input);
    defer rack.deinit(allocator);
    try solution.part1(try rack.countPathsFromYou(allocator));
    try solution.part2(try rack.countPathsFromSvrToOut(allocator));
}

const ServerRack = struct {
    data_paths: std.StringHashMap([][]const u8),

    fn parse(allocator: Allocator, input: *std.Io.Reader) !ServerRack {
        var map = std.StringHashMap([][]const u8).init(allocator);
        errdefer {
            var it = map.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                for (entry.value_ptr.*) |val| {
                    allocator.free(val);
                }
                allocator.free(entry.value_ptr.*);
            }
            map.deinit();
        }
        while (try input.takeDelimiter('\n')) |line| {
            var parts = std.mem.splitSequence(u8, line, ": ");
            const key = parts.next() orelse return error.InvalidInput;
            const duped_key = try allocator.dupe(u8, key);
            const rest = parts.next() orelse return error.InvalidInput;
            var values = std.mem.splitScalar(u8, rest, ' ');
            var alloc_values = try std.ArrayList([]const u8).initCapacity(allocator, 8);
            defer alloc_values.deinit(allocator);
            while (values.next()) |value| {
                const duped = try allocator.dupe(u8, value);
                try alloc_values.append(allocator, duped);
            }

            try map.put(duped_key, try alloc_values.toOwnedSlice(allocator));
        }

        return ServerRack{
            .data_paths = map,
        };
    }

    fn countPathsFromYou(
        self: *const @This(),
        allocator: Allocator,
    ) !usize {
        return self.countPaths(allocator, "you", "out");
    }

    fn countPathsFromSvrToOut(
        self: *const @This(),
        allocator: Allocator,
    ) !usize {
        const paths_to_dac = try self.countPaths(allocator, "svr", "dac");
        const paths_from_dac_to_fft = try self.countPaths(allocator, "dac", "fft");
        const paths_from_fft_to_out = try self.countPaths(allocator, "fft", "out");

        const paths_to_fft = try self.countPaths(allocator, "svr", "fft");
        const paths_from_fft_to_dac = try self.countPaths(allocator, "fft", "dac");
        const paths_from_dac_to_out = try self.countPaths(allocator, "dac", "out");

        return paths_to_dac * paths_from_dac_to_fft * paths_from_fft_to_out +
            paths_to_fft * paths_from_fft_to_dac * paths_from_dac_to_out;
    }

    fn countPaths(
        self: *const @This(),
        allocator: Allocator,
        start: []const u8,
        end: []const u8,
    ) !usize {
        if (!self.data_paths.contains(start)) {
            return 0;
        }

        var in_count = std.StringHashMap(usize).init(allocator);
        defer in_count.deinit();

        var neighbour_it = self.data_paths.valueIterator();
        while (neighbour_it.next()) |neighbors| {
            for (neighbors.*) |neighbor| {
                const count_entry = try in_count.getOrPut(neighbor);
                if (count_entry.found_existing) {
                    count_entry.value_ptr.* += 1;
                } else {
                    count_entry.value_ptr.* = 1;
                }
            }
        }

        const QueueNode = struct {
            name: []const u8,
            node: std.DoublyLinkedList.Node = .{},
        };
        var queue: std.DoublyLinkedList = .{};
        defer {
            while (queue.pop()) |node_ptr| {
                const queue_node: *QueueNode = @fieldParentPtr("node", node_ptr);
                allocator.destroy(queue_node);
            }
        }

        var node_it = self.data_paths.keyIterator();
        while (node_it.next()) |node| {
            if (!in_count.contains(node.*)) {
                const queue_node = try allocator.create(QueueNode);
                queue_node.* = .{
                    .name = node.*,
                };
                queue.append(&queue_node.node);
            }
        }

        var sorted_nodes: std.ArrayList([]const u8) = .empty;
        defer sorted_nodes.deinit(allocator);

        while (queue.popFirst()) |node_ptr| {
            const queue_node: *QueueNode = @fieldParentPtr("node", node_ptr);
            defer allocator.destroy(queue_node);
            try sorted_nodes.append(allocator, queue_node.name);

            const neighbors = self.data_paths.get(queue_node.name) orelse continue;
            for (neighbors) |neighbor| {
                const count = in_count.getPtr(neighbor) orelse continue;
                count.* -= 1;
                if (count.* == 0) {
                    const neighbor_queue_node = try allocator.create(QueueNode);
                    neighbor_queue_node.* = .{
                        .name = neighbor,
                    };
                    queue.append(&neighbor_queue_node.node);
                }
            }
        }

        var visited_counts = std.StringHashMap(usize).init(allocator);
        defer visited_counts.deinit();

        try visited_counts.put(start, 1);

        for (sorted_nodes.items) |node| {
            const neighbours = self.data_paths.get(node) orelse continue;
            const current_count = visited_counts.get(node) orelse 0;
            for (neighbours) |neighbor| {
                const neighbor_count_entry = try visited_counts.getOrPut(neighbor);
                if (neighbor_count_entry.found_existing) {
                    neighbor_count_entry.value_ptr.* += current_count;
                } else {
                    neighbor_count_entry.value_ptr.* = current_count;
                }
            }
        }

        return visited_counts.get(end) orelse 0;
    }

    fn deinit(self: *ServerRack, allocator: Allocator) void {
        var it = self.data_paths.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |val| {
                allocator.free(val);
            }
            allocator.free(entry.value_ptr.*);
        }
        self.data_paths.deinit();
    }
};

test "example" {
    const example_input: []const u8 =
        \\aaa: you hhh
        \\you: bbb ccc
        \\bbb: ddd eee
        \\ccc: ddd eee fff
        \\ddd: ggg
        \\eee: out
        \\fff: out
        \\ggg: out
        \\hhh: ccc fff iii
        \\iii: out
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "5",
        null,
    );
}

test "example 2" {
    const example_input: []const u8 =
        \\svr: aaa bbb
        \\aaa: fft
        \\fft: ccc
        \\bbb: tty
        \\tty: ccc
        \\ccc: ddd eee
        \\ddd: hub
        \\hub: fff
        \\eee: dac
        \\dac: fff
        \\fff: ggg hhh
        \\ggg: out
        \\hhh: out
    ;

    try testing.assertSolutionOutput(
        run,
        example_input,
        "0",
        "2",
    );
}
