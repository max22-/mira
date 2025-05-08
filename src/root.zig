const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("parser.zig");
const SemanticError = @import("program.zig").SemanticError;
const ZigGen = @import("zig_gen.zig");

pub fn compile(allocator: Allocator, file_path: []const u8, source: []const u8) (Allocator.Error || Parser.ParseError || SemanticError)![]u8 {
    var parser = Parser.init(allocator, file_path, source);
    defer parser.deinit();
    var program = parser.parse() catch |err| {
        if (parser.pretty_error) |error_msg| {
            std.debug.print("{s}", .{error_msg});
        }
        return err;
    };
    defer program.deinit(allocator);

    var zig_gen = ZigGen.init(allocator, program);
    return try zig_gen.compile();
}
