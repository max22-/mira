const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("parser.zig");

const MiraError = error{};

pub fn compile(allocator: Allocator, file_path: []const u8, source: []const u8) (Allocator.Error || MiraError)![]u8 {
    var parser = Parser.init(allocator, file_path, source);
    defer parser.deinit();
    std.debug.print("{any} pos={} token={}\n", .{ parser.parse(), parser.pos, parser.lexer.tokens.items[parser.pos] });
    if (parser.pretty_error) |err| {
        std.debug.print("{s}", .{err});
    }

    const result = try allocator.alloc(u8, 5);
    @memcpy(result, "hello");
    return result;
}
