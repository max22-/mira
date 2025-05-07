const std = @import("std");
const Allocator = std.mem.Allocator;
const Lexer = @import("lexer.zig");
const LexerError = Lexer.LexerError;
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;
const Interner = @import("interner.zig");
const Program = @import("program.zig");

const Self = @This();

pub const ParseError = error{
    UnexpectedEOF,
    UnexpectedToken,
};

allocator: Allocator,
file_path: []const u8,
source: []const u8,
lexer: Lexer,
stack_interner: Interner,
string_interner: Interner,
// There is a variable interner, but it is instantiated for each rule.
// So it is reset for each rule. Each rule has a fresh set of variable IDs.
pos: usize,
pretty_error: ?[]const u8,

pub fn init(allocator: Allocator, file_path: []const u8, source: []const u8) Self {
    return Self{
        .allocator = allocator,
        .file_path = file_path,
        .source = source,
        .lexer = Lexer.init(allocator, source),
        .stack_interner = Interner.init(allocator),
        .string_interner = Interner.init(allocator),
        .pos = 0,
        .pretty_error = null,
    };
}

pub fn deinit(self: *Self) void {
    self.lexer.deinit();
    if (self.pretty_error) |err| {
        self.allocator.free(err);
    }
}

const LineColumn = struct {
    line: usize,
    column: usize,
};

fn getLineAndColumn(self: Self, pos: usize) LineColumn {
    var result = LineColumn{ .line = 1, .column = 1 };
    var i: usize = 0;
    while (i < pos) : (i += 1) {
        if (self.source[i] == '\n') {
            result.line += 1;
            result.column = 1;
        } else {
            result.column += 1;
        }
    }
    return result;
}

fn build_error(self: *Self, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    const file_pos = self.lexer.tokens.items[self.pos].pos;
    const line_column = self.getLineAndColumn(file_pos);

    self.pretty_error = try std.fmt.allocPrint(
        self.allocator,
        "{s}:{}:{} " ++ fmt ++ "\n",
        .{ self.file_path, line_column.line, line_column.column } ++ args,
    );
}

fn match(self: *Self, expected_type: TokenType) (Allocator.Error || ParseError)!void {
    const token = self.lexer.get(self.pos) catch |err| switch (err) {
        LexerError.EOFError => {
            try self.build_error("expected {}, found EOF", .{expected_type});
            return ParseError.UnexpectedEOF;
        },
        else => unreachable,
    };
    if (token.type != expected_type) {
        try self.build_error("expected `{}`, found `{}`", .{ expected_type, token.type });
        return ParseError.UnexpectedToken;
    } else {
        self.pos += 1;
    }
}

fn peek(self: Self) ParseError!Token {
    return self.lexer.get(self.pos) catch |err| switch (err) {
        LexerError.EOFError => return ParseError.UnexpectedEOF,
        else => unreachable,
    };
}

fn advance(self: *Self) void {
    self.pos += 1;
}

fn parseTupleItem(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.TupleItem {
    const token = try self.peek();
    const result = switch (token.type) {
        TokenType.identifier => Program.TupleItem{ .string = try self.string_interner.intern(token.val) },
        TokenType.variable => Program.TupleItem{ .variable = try variable_interner.intern(token.val) },
        else => return ParseError.UnexpectedToken,
    };
    self.advance();
    return result;
}

fn parseLhsTuple(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.LhsTuple {
    var tuple = std.ArrayList(Program.TupleItem).init(self.allocator);
    defer tuple.deinit();
    var keep: bool = false;
    while (true) {
        const item = self.parseTupleItem(variable_interner) catch |err| switch (err) {
            ParseError.UnexpectedToken => break,
            else => return err,
        };
        try tuple.append(item);
    }
    const token = try self.peek();
    if (token.type == TokenType.question_mark) {
        keep = true;
        self.advance();
    }
    return Program.LhsTuple{
        .items = try tuple.toOwnedSlice(),
        .keep = keep,
    };
}

fn parseRhsTuple(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.RhsTuple {
    var tuple = std.ArrayList(Program.TupleItem).init(self.allocator);
    defer tuple.deinit();
    while (true) {
        const item = self.parseTupleItem(variable_interner) catch |err| switch (err) {
            ParseError.UnexpectedToken => break,
            ParseError.UnexpectedEOF => break,
            else => return err,
        };
        try tuple.append(item);
    }
    return Program.RhsTuple{ .items = try tuple.toOwnedSlice() };
}

fn parseStack(self: *Self) (Allocator.Error || ParseError)!Program.Stack {
    var result: Program.Stack = undefined;
    try self.match(TokenType.stack_delimiter);
    const token = try self.peek();
    if (token.type == TokenType.identifier) {
        result = try self.stack_interner.intern(token.val);
        self.advance();
    } else {
        result = try self.stack_interner.intern("");
    }
    try self.match(TokenType.stack_delimiter);
    return result;
}

fn parseLhsItem(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.LHSItem {
    const stack = try self.parseStack();
    const tuple = try self.parseLhsTuple(variable_interner);
    return Program.LHSItem{ .stack = stack, .tuple = tuple };
}

fn parseLhs(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.Lhs {
    var items = std.ArrayList(Program.LHSItem).init(self.allocator);
    errdefer {
        for (items.items) |*item| {
            item.deinit(self.allocator);
        }
    }
    defer items.deinit();
    while (true) {
        const token = self.peek() catch break;
        if (token.type == TokenType.stack_delimiter) {
            try items.append(try self.parseLhsItem(variable_interner));
        } else {
            break;
        }
    }
    return Program.Lhs{ .items = try items.toOwnedSlice() };
}

fn parseRhsItem(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.RHSItem {
    const stack = try self.parseStack();
    const tuple = try self.parseRhsTuple(variable_interner);
    return Program.RHSItem{ .stack = stack, .tuple = tuple };
}

fn parseRhs(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.Rhs {
    var items = std.ArrayList(Program.RHSItem).init(self.allocator);
    errdefer {
        for (items.items) |*item| {
            item.deinit(self.allocator);
        }
    }
    defer items.deinit();
    while (true) {
        const token = self.peek() catch return Program.Rhs{ .items = try items.toOwnedSlice() };
        if (token.type == TokenType.stack_delimiter) {
            try items.append(try self.parseRhsItem(variable_interner));
        } else {
            break;
        }
    }
    return Program.Rhs{ .items = try items.toOwnedSlice() };
}

fn parseRule(self: *Self) (Allocator.Error || ParseError)!Program.Rule {
    var rule: Program.Rule = undefined;
    var variable_interner = Interner.init(self.allocator);
    defer variable_interner.deinit();
    try self.match(TokenType.rule_delimiter);
    rule.lhs = try self.parseLhs(&variable_interner);
    errdefer rule.lhs.deinit(self.allocator);
    try self.match(TokenType.rule_delimiter);
    rule.rhs = try self.parseRhs(&variable_interner);
    return rule;
}

fn parseProgram(self: *Self) (Allocator.Error || ParseError)!Program.Program {
    errdefer self.stack_interner.deinit();
    errdefer self.string_interner.deinit();
    var rules = std.ArrayList(Program.Rule).init(self.allocator);
    defer rules.deinit();
    errdefer {
        for (rules.items) |*rule| {
            rule.deinit(self.allocator);
        }
    }

    var initial_state = std.ArrayList(Program.RHSItem).init(self.allocator);
    defer initial_state.deinit();
    errdefer {
        for (initial_state.items) |*item| {
            item.deinit(self.allocator);
        }
    }

    while (true) {
        const token = try self.peek();
        if (token.type == TokenType.eof) {
            break;
        }
        var rule = try self.parseRule();
        if (rule.isInitial()) {
            const initial_state_items = rule.toOwnedInitialStateItems(self.allocator);
            defer self.allocator.free(initial_state_items);
            try initial_state.appendSlice(initial_state_items);
        } else {
            try rules.append(rule);
        }
    }
    return Program.Program{
        .rules = try rules.toOwnedSlice(),
        .initial_state = try initial_state.toOwnedSlice(),
        .stack_interner = self.stack_interner,
        .string_interner = self.string_interner,
    };
}

// the Program is owned by the caller
pub fn parse(self: *Self) (Allocator.Error || ParseError || Program.SemanticError)!Program.Program {
    try self.lexer.lex();
    _ = try self.stack_interner.intern(""); // we intern the "special" stack first
    var program = try self.parseProgram();
    errdefer program.deinit(self.allocator);
    try program.check();
    return program;
}

test "memory leak test" {
    const file_path = "move.nv";
    const source =
        \\|:move: move? :: $x | :dst: $x
        \\|:move:|
        \\
        \\|::|
        \\:: 0
        \\:: 1
        \\:: 2
        \\:: 3
        \\:: 4
    ;
    var parser = Self.init(std.testing.allocator, file_path, source);
    defer parser.deinit();
    var program = try parser.parse();
    defer program.deinit(std.testing.allocator);
}

test "unbound variables in the rhs should cause an error" {
    const file_path = "example.nv";
    const source =
        \\|:: $x | :some_other_stack: $x $y
        \\
        \\|::|
        \\:: 0
        \\:: 1
        \\:: 2
        \\:: 3
        \\:: 4
    ;
    var parser = Self.init(std.testing.allocator, file_path, source);
    defer parser.deinit();
    try std.testing.expectError(Program.SemanticError.UnboundVariable, parser.parse());
}

test "parse error" {
    const file_path = "move.nv";
    const source =
        \\|:move: move? :: $x | :dst: $x
        \\|:move:|
        \\
        \\|::|
        \\:: 0
        \\:: 1
        \\:: 2
        \\:: 3
        \\:: 4 |
    ;
    var parser = Self.init(std.testing.allocator, file_path, source);
    defer parser.deinit();
    try std.testing.expectError(ParseError.UnexpectedToken, parser.parse());
}
