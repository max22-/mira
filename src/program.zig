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
    items: []TupleItem,
    keep: bool,

    pub fn deinit(self: *LhsTuple, allocator: Allocator) void {
        allocator.free(self.items);
    }

    pub fn format(self: LhsTuple, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items, 0..) |item, i| {
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
    items: []TupleItem,

    pub fn deinit(self: *RhsTuple, allocator: Allocator) void {
        allocator.free(self.items);
    }

    pub fn format(self: RhsTuple, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items, 0..) |item, i| {
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

    pub fn deinit(self: *LHSItem, allocator: Allocator) void {
        self.tuple.deinit(allocator);
    }

    pub fn format(self: LHSItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(":{}: {}", .{ self.stack, self.tuple });
    }
};

pub const RHSItem = struct {
    stack: Stack,
    tuple: RhsTuple,

    pub fn deinit(self: *RHSItem, allocator: Allocator) void {
        self.tuple.deinit(allocator);
    }

    pub fn format(self: RHSItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(":{}: {}", .{ self.stack, self.tuple });
    }
};

pub const Lhs = struct {
    items: []LHSItem,

    pub fn deinit(self: *Lhs, allocator: Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }

    pub fn format(self: Lhs, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items, 0..) |item, i| {
            if (i != 0) {
                try writer.print(" ", .{});
            }
            try writer.print("{}", .{item});
        }
    }
};

pub const Rhs = struct {
    items: []RHSItem,

    pub fn deinit(self: *Rhs, allocator: Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
    }

    pub fn format(self: Rhs, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.items, 0..) |item, i| {
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

    pub fn deinit(self: *Rule, allocator: Allocator) void {
        self.lhs.deinit(allocator);
        self.rhs.deinit(allocator);
    }

    pub fn isInitial(self: Rule) bool {
        return self.lhs.items.len == 1 and self.lhs.items[0].stack == 0 and self.lhs.items[0].tuple.items.len == 0;
    }

    // The rule is invalidated. The rhs is owned by the caller.
    // Used for the initial state only.
    pub fn toOwnedInitialStateItems(self: *Rule, allocator: Allocator) []RHSItem {
        self.lhs.deinit(allocator);
        return self.rhs.items;
    }

    pub fn format(self: Rule, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("|{}| {}", .{ self.lhs, self.rhs });
    }
};

pub const Program = struct {
    rules: []Rule,
    initial_state: []RHSItem,

    pub fn deinit(self: *Program, allocator: Allocator) void {
        for (self.rules) |*rule| {
            rule.deinit(allocator);
        }
        allocator.free(self.rules);
        for (self.initial_state) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.initial_state);
    }

    pub fn add_rule(self: *Program, rule: Rule) Allocator.Error!void {
        try self.rules.append(rule);
    }

    pub fn appendToInitialState(self: *Program, initial_state_items: Rhs) Allocator.Error!void {
        defer initial_state_items.items.deinit();
        try self.initial_state.appendSlice(initial_state_items.items.items);
    }

    pub fn format(self: Program, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        for (self.rules) |rule| {
            try writer.print("{}\n", .{rule});
        }
        // initial state :
        try writer.print("|::|", .{});
        for (self.initial_state) |rhs| {
            try writer.print(" {}", .{rhs});
        }
    }
};
