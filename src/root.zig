const std = @import("std");
const Allocator = std.mem.Allocator;
const Lexer = @import("lexer.zig");
//const testing = std.testing;

const MiraError = error{};

pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn compile(allocator: Allocator, source: []const u8) (Allocator.Error || MiraError)![]u8 {
    var lexer = Lexer.init(allocator, source);
    defer lexer.deinit();
    const tokens = try lexer.lex();
    for (tokens.items) |token| {
        std.debug.print("{}\t{s}\t{}\n", .{ token.type, token.val, token.pos });
    }

    const result = try allocator.alloc(u8, 5);
    @memcpy(result, "hello");
    return result;
}

//test "basic add functionality" {
//    try testing.expect(add(3, 7) == 10);
//}
