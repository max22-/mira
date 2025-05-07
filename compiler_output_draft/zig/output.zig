const std = @import("std");
const Allocator = std.mem.Allocator;

const MiraError = error{
    TupleOverflow,
    StackUnderflow,
    RuleFailed,
};

const Interned = u32;

fn Tuple(comptime n: usize) type {
    return struct {
        data: [n]Interned,
        arity: usize,

        fn init() Tuple(n) {
            return Tuple(n){
                .data = [_]Interned{0} ** n,
                .arity = 0,
            };
        }

        fn reset(self: *Tuple(n)) void {
            @memset(self.data, 0);
            self.arity = 0;
        }

        fn append(self: *Tuple(n), i: Interned) MiraError!void {
            if (self.arity >= n) {
                return MiraError.TupleOverflow;
            }
            self.data[self.arity] = i;
            self.arity += 1;
        }

        fn fromSlice(slice: []const Interned) Tuple(n) {
            var result: Tuple(n) = undefined;
            if (slice.len > n) {
                unreachable;
            }
            for (0..slice.len) |i| {
                result.data[i] = slice[i];
            }
            result.arity = slice.len;
            return result;
        }
    };
}

fn Stack(comptime n: usize) type {
    return struct {
        data: std.ArrayList(Tuple(n)),
        len: usize,

        fn init(allocator: Allocator) Stack(n) {
            return Stack(n){
                .data = std.ArrayList(Tuple(n)).init(allocator),
                .len = 0,
            };
        }

        fn deinit(self: *Stack(n)) void {
            self.data.deinit();
        }

        fn push(self: *Stack(n), tuple: Tuple(n)) Allocator.Error!void {
            try self.data.append(tuple);
            self.len += 1;
        }

        fn peek(self: Stack(n)) MiraError!Tuple(n) {
            if (self.data.getLastOrNull()) |last| {
                return last;
            } else {
                return MiraError.StackUnderflow;
            }
        }

        fn pop(self: *Stack(n)) MiraError!Tuple(n) {
            const last = try self.peek();
            self.len -= 1;
            return last;
        }

        fn commitSuccess(self: *Stack(n)) void {
            self.data.shrinkRetainingCapacity(self.len);
        }

        fn commitFailure(self: *Stack(n)) void {
            self.len = self.data.items.len;
        }
    };
}

const PatternItemType = enum { value, variable };
const PatternItem = union(PatternItemType) {
    value: Interned,
    variable: Interned,
};

const Program = struct {
    stack0: Stack(1),
    stack1: Stack(1),
    stack2: Stack(1),

    fn init(allocator: Allocator) Allocator.Error!Program {
        var p = Program{
            .stack0 = Stack(1).init(allocator),
            .stack1 = Stack(1).init(allocator),
            .stack2 = Stack(1).init(allocator),
        };
        try p.stack0.push(Tuple(1).fromSlice(&[_]Interned{1}));
        try p.stack0.push(Tuple(1).fromSlice(&[_]Interned{2}));
        try p.stack0.push(Tuple(1).fromSlice(&[_]Interned{3}));
        try p.stack0.push(Tuple(1).fromSlice(&[_]Interned{4}));
        try p.stack0.push(Tuple(1).fromSlice(&[_]Interned{5}));

        try p.stack1.push(Tuple(1).fromSlice(&[_]Interned{0}));
        return p;
    }

    fn deinit(self: *Program) void {
        self.stack0.deinit();
        self.stack1.deinit();
        self.stack2.deinit();
    }

    fn commitFailure(self: *Program) void {
        self.stack0.commitFailure();
        self.stack1.commitFailure();
        self.stack2.commitFailure();
    }

    fn commitSuccess(self: *Program) void {
        self.stack0.commitSuccess();
        self.stack1.commitSuccess();
        self.stack2.commitSuccess();
    }

    fn match(comptime n: usize, stack_tuple: Tuple(n), rule_tuple: []const PatternItem, vars: []?Interned) bool {
        if (stack_tuple.arity != rule_tuple.len) {
            return false;
        }
        for (rule_tuple, 0..) |item, i| {
            switch (item) {
                .value => if (stack_tuple.data[i] != item.value) return false,
                .variable => if (vars[i]) |v| {
                    if (stack_tuple.data[i] != v) {
                        return false;
                    }
                } else {
                    vars[i] = stack_tuple.data[i];
                },
            }
        }
        return true;
    }

    fn rule0(self: *Program) (Allocator.Error || MiraError)!void {
        errdefer self.commitFailure();

        var vars = [_]?Interned{null} ** 1;

        const t0 = self.stack1.peek() catch |err| switch (err) {
            MiraError.StackUnderflow => return MiraError.RuleFailed,
            else => unreachable,
        };
        if (!match(1, t0, &[_]PatternItem{.{ .value = 0 }}, &vars))
            return MiraError.RuleFailed;

        const t2 = self.stack0.pop() catch |err| switch (err) {
            MiraError.StackUnderflow => return MiraError.RuleFailed,
            else => unreachable,
        };
        if (!match(1, t2, &[_]PatternItem{.{ .variable = 0 }}, &vars))
            return MiraError.RuleFailed;

        self.commitSuccess();
        try self.stack2.push(Tuple(1).fromSlice(&[_]Interned{vars[0].?}));
    }

    fn rule1(self: *Program) (Allocator.Error || MiraError)!void {
        errdefer self.commitFailure();

        const t1 = self.stack1.pop() catch |err| switch (err) {
            MiraError.StackUnderflow => return MiraError.RuleFailed,
            else => return err,
        };

        if (t1.arity != 1) {
            return MiraError.RuleFailed;
        }

        if (t1.data[0] != 0) {
            return MiraError.RuleFailed;
        }

        self.commitSuccess();
    }

    fn run(self: *Program) (Allocator.Error || MiraError)!void {
        loop: while (true) {
            blk0: {
                self.rule0() catch |err| switch (err) {
                    MiraError.RuleFailed => break :blk0,
                    else => return err,
                };
                continue :loop;
            }

            blk1: {
                self.rule1() catch |err| switch (err) {
                    MiraError.RuleFailed => break :blk1,
                    else => return err,
                };
                continue :loop;
            }

            break;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var p = try Program.init(allocator);
    defer p.deinit();
    try p.run();
    std.debug.print("stack0:\n", .{});
    for (p.stack0.data.items) |t| {
        std.debug.print("{any}\n", .{t});
    }
    std.debug.print("stack1:\n", .{});
    for (p.stack1.data.items) |t| {
        std.debug.print("{any}\n", .{t});
    }
    std.debug.print("stack2:\n", .{});
    for (p.stack2.data.items) |t| {
        std.debug.print("{any}\n", .{t});
    }
    std.debug.print("{}\n", .{p});
}
