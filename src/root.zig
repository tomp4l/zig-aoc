//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn runSolution(allocator: Allocator, year: u16, day: u16) !void {
    switch (year) {
        2019 => {
            const Year = @import("2019/year.zig");
            try runYear(allocator, Year, 2019, day);
        },
        else => {
            return error.YearNotImplemented;
        },
    }
}

pub const Solution = struct {
    writer: *std.Io.Writer,

    pub fn part1(self: *const Solution, value: anytype) !void {
        try self.part(1, value);
    }

    pub fn part2(self: *const Solution, value: anytype) !void {
        try self.part(2, value);
    }

    fn part(self: *const Solution, p: u2, value: anytype) !void {
        const t = @TypeOf(value);
        switch (@typeInfo(t)) {
            .pointer => |type_info| {
                switch (type_info.size) {
                    .one => {
                        try self.part(p, value.*);
                    },
                    .slice => {
                        if (type_info.child == u8) {
                            try self.writer.print("Part {d}: {s}\n", .{ p, value });
                        } else {
                            return error.UnhandledOutputType;
                        }
                    },
                    .many, .c => {
                        return error.UnhandledOutputType;
                    },
                }
            },
            .array => |type_info| {
                if (type_info.child == u8) {
                    try self.writer.print("Part {d}: {s}\n", .{ p, value });
                } else {
                    return error.UnhandledOutputType;
                }
            },
            else => {
                try self.writer.print("Part {d}: {any}\n", .{ p, value });
            },
        }
    }
};

fn runYear(allocator: Allocator, Year: type, year: u16, day: u16) !void {
    switch (day) {
        inline 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 => |d| {
            const day_name = comptime std.fmt.comptimePrint("day{}", .{d});

            if (@hasDecl(Year, day_name)) {
                const runnable_day = @field(Year, day_name);

                var filename_buffer: [20]u8 = undefined;
                const filename = std.fmt.bufPrint(&filename_buffer, "input/{}/day{}.txt", .{ year, d }) catch @panic("filename buffer too small");

                const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
                defer file.close();
                var file_buffer: [4096]u8 = undefined;
                var reader = file.readerStreaming(&file_buffer);

                var stdout_buffer: [4096]u8 = undefined;
                var stdout = std.fs.File.stdout().writerStreaming(&stdout_buffer);
                var solution = Solution{
                    .writer = &stdout.interface,
                };

                const type_info = @typeInfo(@TypeOf(runnable_day.run));

                if (type_info.@"fn".params.len == 3) {
                    try runnable_day.run(allocator, &reader.interface, &solution);
                } else {
                    comptime var day_instance = runnable_day{};
                    try day_instance.run(allocator, &reader.interface, &solution);
                }
                try solution.writer.flush();
            } else {
                return error.DayNotImplemented;
            }
        },
        else => return error.InvalidDay,
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
