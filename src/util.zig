const std = @import("std");

fn HeapsIterator(T: type, size: comptime_int) type {
    return struct {
        const Self = @This();

        phase_settings: [size]T,
        c: [size]u8,
        i: usize,
        first: bool,

        pub fn init(phase_settings: [size]T) Self {
            return Self{
                .phase_settings = phase_settings,
                .i = 0,
                .c = @splat(0),
                .first = true,
            };
        }

        pub fn next(self: *Self) ?[]const T {
            if (self.first) {
                self.first = false;
                return self.phase_settings[0..];
            }

            while (self.i < size) {
                if (self.c[self.i] < self.i) {
                    if ((self.i & 1) == 0) {
                        std.mem.swap(T, &self.phase_settings[0], &self.phase_settings[self.i]);
                    } else {
                        std.mem.swap(T, &self.phase_settings[self.c[self.i]], &self.phase_settings[self.i]);
                    }
                    self.c[self.i] += 1;
                    self.i = 0;
                    return self.phase_settings[0..];
                } else {
                    self.c[self.i] = 0;
                    self.i += 1;
                }
            }
            return null;
        }
    };
}

pub fn permutationIterator(size: comptime_int, data: []const u8) !HeapsIterator(u8, size) {
    if (data.len != size) {
        return error.InvalidInput;
    }
    var phase_settings: [size]u8 = undefined;
    @memcpy(&phase_settings, data);
    return HeapsIterator(u8, size).init(phase_settings);
}

test "heaps iterator" {
    const phase_settings: [3]u8 = .{ 0, 1, 2 };
    var it = HeapsIterator(u8, 3).init(phase_settings);

    var results: [6][3]u8 = .{ .{ 0, 1, 2 }, .{ 1, 0, 2 }, .{ 2, 0, 1 }, .{ 0, 2, 1 }, .{ 1, 2, 0 }, .{ 2, 1, 0 } };
    var index: usize = 0;

    while (true) {
        const next = it.next();
        if (next == null) break;
        try std.testing.expectEqualSlices(
            u8,
            &results[index],
            next.?,
        );
        index += 1;
    }
    try std.testing.expect(index == results.len);
}
