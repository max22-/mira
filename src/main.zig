const std = @import("std");
const mira = @import("mira");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("usage: {s} file.nv\n", .{args[0]});
        return;
    }

    const file_path = args[1];
    const source = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(source);
    const result = try mira.compile(allocator, file_path, source);
    defer allocator.free(result);
}
