const std = @import("std");

const Self = @This();
pub const InternedString = u32;

strings: std.StringArrayHashMap(InternedString),
counter: InternedString,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .strings = std.StringArrayHashMap(u32).init(allocator),
        .counter = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.strings.deinit();
}

pub fn intern(self: *Self, string: []const u8) std.mem.Allocator.Error!InternedString {
    const v = self.strings.get(string);
    if (v) |result| {
        return result;
    } else {
        const result = self.counter;
        try self.strings.put(string, result);
        self.counter += 1;
        return result;
    }
}

const expectEqual = std.testing.expectEqual;

test "basic test" {
    var interner = Self.init(std.testing.allocator);
    defer interner.deinit();
    const s1 = try interner.intern("Hello, World!");
    try expectEqual(0, s1);
    const s2 = try interner.intern("Hello, World!");
    try expectEqual(0, s2);
    const s3 = try interner.intern("foo");
    try expectEqual(1, s3);
    const s4 = try interner.intern("bar");
    try expectEqual(2, s4);
    const s5 = try interner.intern("foo");
    try expectEqual(1, s5);
}
