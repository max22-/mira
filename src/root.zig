const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("parser.zig");

pub fn compile(allocator: Allocator, file_path: []const u8, source: []const u8) (Allocator.Error || Parser.ParseError)![]u8 {
    var parser = Parser.init(allocator, file_path, source);
    defer parser.deinit();
    var program = parser.parse() catch |err| {
        if (parser.pretty_error) |error_msg| {
            std.debug.print("{s}", .{error_msg});
        }
        return err;
    };
    defer program.deinit(allocator);
    std.debug.print("{}\n", .{program});

    const result = try allocator.alloc(u8, 5);
    @memcpy(result, "hello");
    return result;
}
