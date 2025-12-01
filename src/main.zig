const std = @import("std");
const aoc = @import("aoc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    // Get year argument
    const year_str = args.next() orelse {
        std.debug.print("Usage: aoc <year> <day>\n", .{});
        std.debug.print("Example: aoc 2019 1\n", .{});
        return error.MissingArguments;
    };
    const year = try std.fmt.parseInt(u16, year_str, 10);

    // Get day argument
    const day_str = args.next() orelse {
        std.debug.print("Usage: aoc <year> <day>\n", .{});
        std.debug.print("Example: aoc 2019 1\n", .{});
        return error.MissingArguments;
    };
    const day = try std.fmt.parseInt(u16, day_str, 10);

    try aoc.runSolution(allocator, year, day);
}
