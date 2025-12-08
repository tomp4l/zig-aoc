const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Solution = root.Solution;

const testing = @import("../testing.zig");
const parsing = @import("../parsing.zig");

pairs_to_connect: usize = 1000,

pub fn run(self: @This(), allocator: Allocator, input: *std.Io.Reader, solution: *Solution) !void {
    const coords = try parsing.parseAny(allocator, Coord.parse, input, '\n');
    defer allocator.free(coords);

    const result = try largestThreeAndLastConnection(allocator, coords, self.pairs_to_connect);
    try solution.part1(result.top_three_product);
    const part2: i64 = @as(i64, result.last_connection[0].x) * @as(i64, result.last_connection[1].x);
    try solution.part2(part2);
}

const Coord = struct {
    x: i32,
    y: i32,
    z: i32,

    fn parse(s: []const u8) !Coord {
        var parts = std.mem.splitScalar(u8, s, ',');

        const x = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidCoordinate, 10);
        const y = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidCoordinate, 10);
        const z = try std.fmt.parseInt(i32, parts.next() orelse return error.InvalidCoordinate, 10);
        return .{ .x = x, .y = y, .z = z };
    }
};

const PossibleConnection = struct {
    a: *const Coord,
    b: *const Coord,
    distance_squared: u64,

    fn create(a: *const Coord, b: *const Coord) PossibleConnection {
        const dx: i64 = a.x - b.x;
        const dy: i64 = a.y - b.y;
        const dz: i64 = a.z - b.z;
        const dx2: usize = @intCast(dx * dx);
        const dy2: usize = @intCast(dy * dy);
        const dz2: usize = @intCast(dz * dz);
        const dist_sq = dx2 + dy2 + dz2;

        return .{
            .a = a,
            .b = b,
            .distance_squared = dist_sq,
        };
    }

    fn lessThan(context: void, a: @This(), b: @This()) bool {
        _ = context;
        return a.distance_squared < b.distance_squared;
    }
};

const Circuit = struct {
    nodes: std.ArrayList(*const Coord),

    fn init(allocator: Allocator, coord: *const Coord) !Circuit {
        var nodes = try std.ArrayList(*const Coord).initCapacity(allocator, 8);
        nodes.appendAssumeCapacity(coord);
        return Circuit{
            .nodes = nodes,
        };
    }

    fn merge(self: *Circuit, allocator: Allocator, other: *Circuit) !void {
        var from, var to = if (self.nodes.items.len >= other.nodes.items.len)
            .{ self, other }
        else
            .{ other, self };
        const s = try to.nodes.addManyAsSlice(allocator, from.nodes.items.len);
        @memcpy(s, from.nodes.items);
        from.nodes.clearAndFree(allocator);
    }

    fn contains(self: *const @This(), coord: *const Coord) bool {
        return std.mem.findScalar(*const Coord, self.nodes.items, coord) != null;
    }

    fn size(self: *const @This()) usize {
        return self.nodes.items.len;
    }

    fn deinit(self: *Circuit, allocator: Allocator) void {
        self.nodes.deinit(allocator);
    }
};

const Result = struct {
    top_three_product: u64,
    last_connection: struct { Coord, Coord },
};

fn largestThreeAndLastConnection(allocator: Allocator, points: []Coord, pairs_to_connect: usize) !Result {
    const connection_count = points.len * (points.len - 1) / 2;
    var all_connections = try allocator.alloc(PossibleConnection, connection_count);
    defer allocator.free(all_connections);
    var connections: usize = 0;
    for (points, 0..) |*a, i| {
        for (points[i + 1 ..]) |*b| {
            all_connections[connections] = PossibleConnection.create(a, b);
            connections += 1;
        }
    }
    std.mem.sort(PossibleConnection, all_connections, {}, PossibleConnection.lessThan);

    var circuits = try allocator.alloc(Circuit, points.len);
    var allocated_circuits: usize = 0;
    defer {
        for (0..allocated_circuits) |i| {
            circuits[i].deinit(allocator);
        }
        allocator.free(circuits);
    }
    for (points, 0..) |*point, i| {
        circuits[i] = try Circuit.init(allocator, point);
        allocated_circuits = i + 1;
    }

    var top_three_product: u64 = 1;
    for (all_connections, 1..) |connection, connected| {
        var circuit_a: ?*Circuit = null;
        var circuit_b: ?*Circuit = null;
        for (circuits) |*circuit| {
            if (circuit.size() == 0) continue;
            if (circuit.contains(connection.a)) {
                circuit_a = circuit;
            }
            if (circuit.contains(connection.b)) {
                circuit_b = circuit;
            }
            if (circuit_a != null and circuit_b != null) {
                break;
            }
        }
        if (circuit_a != circuit_b) {
            try circuit_a.?.merge(allocator, circuit_b.?);
        }

        if (connected == pairs_to_connect) {
            var sizes = try allocator.alloc(usize, points.len);
            defer allocator.free(sizes);
            for (circuits, 0..) |circuit, j| {
                sizes[j] = circuit.size();
            }
            std.mem.sort(usize, sizes, {}, std.sort.desc(usize));
            for (0..3) |j| {
                top_three_product *= sizes[j];
            }
        }

        if (circuit_a.?.nodes.items.len + circuit_b.?.nodes.items.len == points.len) {
            return .{
                .top_three_product = top_three_product,
                .last_connection = .{ connection.a.*, connection.b.* },
            };
        }
    }

    return error.NotAllConnected;
}

test "example" {
    const example_input: []const u8 =
        \\162,817,812
        \\57,618,57
        \\906,360,560
        \\592,479,940
        \\352,342,300
        \\466,668,158
        \\542,29,236
        \\431,825,988
        \\739,650,466
        \\52,470,668
        \\216,146,977
        \\819,987,18
        \\117,168,530
        \\805,96,715
        \\346,949,466
        \\970,615,88
        \\941,993,340
        \\862,61,35
        \\984,92,344
        \\425,690,689
    ;

    const self: @This() = .{
        .pairs_to_connect = 10,
    };

    try testing.assertSolutionOutput(
        self,
        example_input,
        "40",
        "25272",
    );
}
