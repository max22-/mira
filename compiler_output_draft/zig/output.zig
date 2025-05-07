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

const Program = struct {
    stack0: Stack(1),
    stack1: Stack(1),
    stack2: Stack(1),

    vars: [1]Interned,

    fn init(allocator: Allocator) Allocator.Error!Program {
        var p = Program{
            .stack0 = Stack(1).init(allocator),
            .stack1 = Stack(1).init(allocator),
            .stack2 = Stack(1).init(allocator),
            .vars = [_]Interned{0} ** 1,
        };
        try p.stack0.push(.{ .data = .{1}, .arity = 1 });
        try p.stack0.push(.{ .data = .{2}, .arity = 1 });
        try p.stack0.push(.{ .data = .{3}, .arity = 1 });
        try p.stack0.push(.{ .data = .{4}, .arity = 1 });
        try p.stack0.push(.{ .data = .{5}, .arity = 1 });

        try p.stack1.push(.{ .data = .{0}, .arity = 1 });
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

    fn rule0(self: *Program) (Allocator.Error || MiraError)!void {
        errdefer self.commitFailure();

        const t1 = self.stack1.peek() catch |err| switch (err) {
            MiraError.StackUnderflow => return MiraError.RuleFailed,
            else => return err,
        };
        if (t1.arity != 1) {
            return MiraError.RuleFailed;
        }
        if (t1.data[0] != 0) {
            return MiraError.RuleFailed;
        }
        std.debug.print("stack0 = {}\n", .{self.stack0});
        const t2 = self.stack0.pop() catch |err| switch (err) {
            MiraError.StackUnderflow => return MiraError.RuleFailed,
            else => return err,
        };
        if (t2.arity != 1) {
            return MiraError.RuleFailed;
        }
        self.vars[0] = t2.data[0];

        self.commitSuccess();
        var t3 = Tuple(1).init();
        try t3.append(self.vars[0]);
        try self.stack2.push(t3);
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
