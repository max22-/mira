const std = @import("std");
const Allocator = std.mem.Allocator;
const InternedString = @import("interner.zig").InternedString;

const Self = @This();

pub const Stack = InternedString;
pub const TupleItemType = enum {
    string,
    variable,
};
pub const TupleItem = union(TupleItemType) {
    string: InternedString,
    variable: InternedString,

    pub fn format(self: TupleItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .string => try writer.print("{}", .{self.string}),
            .variable => try writer.print("${}", .{self.variable}),
        }
    }
};

pub const LhsTuple = struct {
    items: std.ArrayList(TupleItem),
    keep: bool,

    pub fn init(allocator: Allocator) LhsTuple {
        return LhsTuple{
            .items = std.ArrayList(TupleItem).init(allocator),
            .keep = false,
        };
    }

    pub fn deinit(self: *LhsTuple) void {
        self.items.deinit();
    }

    pub fn format(self: LhsTuple, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items.items, 0..) |item, i| {
            if (i != 0) {
                try writer.print(" ", .{});
            }
            try writer.print("{}", .{item});
        }
        if (self.keep) {
            try writer.print("?", .{});
        }
    }
};

pub const RhsTuple = struct {
    items: std.ArrayList(TupleItem),

    pub fn init(allocator: Allocator) RhsTuple {
        return RhsTuple{
            .items = std.ArrayList(TupleItem).init(allocator),
        };
    }

    pub fn deinit(self: *RhsTuple) void {
        self.items.deinit();
    }

    pub fn format(self: RhsTuple, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items.items, 0..) |item, i| {
            if (i != 0) {
                try writer.print(" ", .{});
            }
            try writer.print("{}", .{item});
        }
    }
};

pub const LHSItem = struct {
    stack: Stack,
    tuple: LhsTuple,

    fn deinit(self: *LHSItem) void {
        self.tuple.deinit();
    }

    pub fn format(self: LHSItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(":{}:{}", .{ self.stack, self.tuple });
    }
};

pub const RHSItem = struct {
    stack: Stack,
    tuple: RhsTuple,

    fn deinit(self: *RHSItem) void {
        self.tuple.deinit();
    }

    pub fn format(self: RHSItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(":{}:{}", .{ self.stack, self.tuple });
    }
};

pub const Lhs = struct {
    items: std.ArrayList(LHSItem),

    pub fn init(allocator: Allocator) Lhs {
        return Lhs{ .items = std.ArrayList(LHSItem).init(allocator) };
    }

    pub fn deinit(self: *Lhs) void {
        for (self.items.items) |*item| {
            item.deinit();
        }
        self.items.deinit();
    }

    pub fn format(self: Lhs, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items.items, 0..) |item, i| {
            if (i != 0) {
                try writer.print(" ", .{});
            }
            try writer.print("{}", .{item});
        }
    }
};

pub const Rhs = struct {
    items: std.ArrayList(RHSItem),

    pub fn init(allocator: Allocator) Rhs {
        return Rhs{ .items = std.ArrayList(RHSItem).init(allocator) };
    }

    pub fn deinit(self: *Rhs) void {
        for (self.items.items) |*item| {
            item.deinit();
        }
        self.items.deinit();
    }

    pub fn format(self: Rhs, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items.items, 0..) |item, i| {
            if (i != 0) {
                try writer.print(" ", .{});
            }
            try writer.print("{}", .{item});
        }
    }
};

pub const Rule = struct {
    lhs: Lhs,
    rhs: Rhs,

    pub fn deinit(self: *Rule) void {
        self.lhs.deinit();
        self.rhs.deinit();
    }

    pub fn format(self: Rule, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("|{}| {}", .{ self.lhs, self.rhs });
    }
};

pub const Program = struct {
    rules: std.ArrayList(Rule),
    initial_state: std.ArrayList(RHSItem),

    pub fn init(allocator: Allocator) Program {
        return Program{
            .rules = std.ArrayList(Rule).init(allocator),
            .initial_state = std.ArrayList(RHSItem).init(allocator),
        };
    }

    pub fn deinit(self: *Program) void {
        for (self.rules.items) |*rule| {
            rule.deinit();
        }
        self.rules.deinit();
        self.initial_state.deinit();
    }

    pub fn add_rule(self: *Program, rule: Rule) Allocator.Error!void {
        try self.rules.append(rule);
    }

    pub fn add_initial_state_item(self: *Program, initial_state_item: RHSItem) Allocator.Error!void {
        try self.initial_state.append(initial_state_item);
    }

    pub fn format(self: Program, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.rules.items) |rule| {
            try writer.print("{}\n", .{rule});
        }
    }
};
