const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Program = @import("program.zig");

const Self = @This();

output: ArrayList(u8),
program: Program.Program,

pub fn init(allocator: Allocator, program: Program.Program) Self {
    return Self{
        .output = ArrayList(u8).init(allocator),
        .program = program,
    };
}

pub fn deinit(self: *Self) void {
    self.output.deinit();
}

pub fn emit(self: *Self, code: []const u8) Allocator.Error!void {
    try self.output.writer().writeAll(code);
}

pub fn fmtEmit(self: *Self, comptime code: []const u8, args: anytype) Allocator.Error!void {
    const writer = self.output.writer();
    try std.fmt.format(writer, code, args);
    //try writer.print(code, args);
}

// The caller owns the returned slice
pub fn compile(self: *Self) Allocator.Error![]u8 {
    try self.emit(
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\
        \\const MiraError = error{
        \\    TupleOverflow,
        \\    StackUnderflow,
        \\    RuleFailed,
        \\};
        \\
        \\const Interned = u32;
        \\
        \\fn Tuple(comptime n: usize) type {
        \\    return struct {
        \\        data: [n]Interned,
        \\        arity: usize,
        \\
        \\        fn init() Tuple(n) {
        \\            return Tuple(n){
        \\                .data = [_]Interned{0} ** n,
        \\                .arity = 0,
        \\            };
        \\        }
        \\
        \\        fn reset(self: *Tuple(n)) void {
        \\            @memset(self.data, 0);
        \\            self.arity = 0;
        \\        }
        \\
        \\        fn append(self: *Tuple(n), i: Interned) MiraError!void {
        \\            if (self.arity >= n) {
        \\                return MiraError.TupleOverflow;
        \\            }
        \\            self.data[self.arity] = i;
        \\            self.arity += 1;
        \\        }
        \\    };
        \\}
        \\
        \\fn Stack(comptime n: usize) type {
        \\    return struct {
        \\        data: std.ArrayList(Tuple(n)),
        \\        len: usize,
        \\
        \\        fn init(allocator: Allocator) Stack(n) {
        \\            return Stack(n){
        \\                .data = std.ArrayList(Tuple(n)).init(allocator),
        \\                .len = 0,
        \\            };
        \\        }
        \\
        \\        fn deinit(self: *Stack(n)) void {
        \\            self.data.deinit();
        \\        }
        \\
        \\        fn push(self: *Stack(n), tuple: Tuple(n)) Allocator.Error!void {
        \\            try self.data.append(tuple);
        \\            self.len += 1;
        \\        }
        \\
        \\        fn peek(self: Stack(n)) MiraError!Tuple(n) {
        \\            if (self.data.getLastOrNull()) |last| {
        \\                return last;
        \\            } else {
        \\                return MiraError.StackUnderflow;
        \\            }
        \\        }
        \\
        \\        fn pop(self: *Stack(n)) MiraError!Tuple(n) {
        \\            const last = try self.peek();
        \\            self.len -= 1;
        \\            return last;
        \\        }
        \\
        \\        fn commitSuccess(self: *Stack(n)) void {
        \\            self.data.shrinkRetainingCapacity(self.len);
        \\        }
        \\
        \\        fn commitFailure(self: *Stack(n)) void {
        \\            self.len = self.data.items.len;
        \\        }
        \\    };
        \\}
        \\
        \\const PatternItemType = enum { value, variable };
        \\const PatternItem = union(PatternItemType) {
        \\    value: Interned,
        \\    variable: Interned,
        \\};
        \\
        \\const Program = struct {
        \\
    );
    const stacks_count = self.program.getStackCount();
    for (0..stacks_count) |i| {
        const arity = self.program.getStackArity(@intCast(i));
        try self.fmtEmit("    stack{}: Stack({}),\n", .{ i, arity });
    }
    const vars_count = self.program.getVarCount();
    try self.emit("\n");
    try self.emit(
        \\
        \\    fn init(allocator: Allocator) Allocator.Error!Program {
        \\        var p = Program{
        \\
    );
    for (0..stacks_count) |i| {
        const arity = self.program.getStackArity(@intCast(i));
        try self.fmtEmit(
            "            .stack{} = Stack({}).init(allocator),\n",
            .{ i, arity },
        );
    }
    try self.emit("        };\n");
    for (self.program.initial_state) |rhs_item| {
        const stack = rhs_item.stack;
        const stack_arity = self.program.getStackArity(stack);
        try self.fmtEmit(
            "        try p.stack{}.push(Tuple({}).fromSlice(&[_]Interned{{",
            .{ stack, stack_arity },
        );
        for (rhs_item.tuple.items, 0..) |tuple_item, i| {
            if (i != 0) {
                try self.emit(", ");
            }
            switch (tuple_item) {
                .variable => unreachable,
                .string => try self.fmtEmit("{}", .{tuple_item.string}),
            }
        }
        try self.emit("}));\n");
    }
    try self.emit(
        \\        return p;
        \\    }
        \\
        \\    fn deinit(self: *Program) void {
        \\
    );
    for (0..stacks_count) |i| {
        try self.fmtEmit("        self.stack{}.deinit();\n", .{i});
    }
    try self.emit(
        \\    }
        \\
        \\    fn commitFailure(self: *Program) void {
        \\
    );
    for (0..stacks_count) |i| {
        try self.fmtEmit("        self.stack{}.commitFailure();\n", .{i});
    }
    try self.emit(
        \\    }
        \\
        \\    fn commitSuccess(self: *Program) void {
        \\
    );
    for (0..stacks_count) |i| {
        try self.fmtEmit("        self.stack{}.commitSuccess();\n", .{i});
    }
    try self.emit("    }\n\n");

    try self.emit(
        \\    fn match(comptime n: usize, stack_tuple: Tuple(n), rule_tuple: []const PatternItem, vars: []?Interned) bool {
        \\        if (stack_tuple.arity != rule_tuple.len) {
        \\            return false;
        \\        }
        \\        for (rule_tuple, 0..) |item, i| {
        \\            switch (item) {
        \\                .value => if (stack_tuple.data[i] != item.value) return false,
        \\                .variable => if (vars[i]) |v| {
        \\                    if (stack_tuple.data[i] != v) {
        \\                        return false;
        \\                    }
        \\                } else {
        \\                    vars[i] = stack_tuple.data[i];
        \\                },
        \\            }
        \\        }
        \\        return true;
        \\    }
        \\
        \\
    );

    for (self.program.rules, 0..) |rule, i| {
        try self.fmtEmit(
            "    fn rule{}(self: *Program) (Allocator.Error || MiraError)!void {{\n",
            .{i},
        );
        try self.emit("        errdefer self.commitFailure();\n\n");
        try self.fmtEmit(
            "        var vars = [_]?Interned{{null}} ** {};\n",
            .{vars_count},
        );
        for (rule.lhs.items, 0..) |item, j| {
            const op = if (item.tuple.keep) "peek" else "pop";
            try self.fmtEmit(
                "        const t{} = self.stack{}.{s}() catch |err| switch (err) {{\n",
                .{ j, item.stack, op },
            );
            try self.emit(
                \\            MiraError.StackUnderflow => return MiraError.RuleFailed,
                \\            else => unreachable,
                \\        };
                \\
            );
            try self.fmtEmit(
                "        if(!match({}, t{}, &[_]PatternItem{{",
                .{
                    self.program.getStackArity(item.stack),
                    j,
                },
            );
            for (item.tuple.items, 0..) |tuple_item, k| {
                if (k != 0) {
                    try self.emit(", ");
                }
                switch (tuple_item) {
                    .string => try self.fmtEmit(".{{ .value = {} }}", .{tuple_item.string}),
                    .variable => try self.fmtEmit(".{{ .variable = {} }}", .{tuple_item.variable}),
                }
            }
            try self.emit(
                \\}, &vars))
                \\            return MiraError.RuleFailed;
                \\
            );
        }
        try self.emit(
            \\        self.commitSuccess();
            \\    }
            \\
            \\
        );
    }

    try self.emit("};\n");

    return self.output.toOwnedSlice();
}
