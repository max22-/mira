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
    self.stack_interner.deinit();
    self.string_interner.deinit();
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
    var tuple = Program.LhsTuple.init(self.allocator);
    errdefer tuple.deinit();
    while (true) {
        const item = self.parseTupleItem(variable_interner) catch |err| switch (err) {
            ParseError.UnexpectedToken => break,
            else => return err,
        };
        try tuple.items.append(item);
    }
    const token = try self.peek();
    if (token.type == TokenType.question_mark) {
        tuple.keep = true;
        self.advance();
    }
    return tuple;
}

fn parseRhsTuple(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.RhsTuple {
    var tuple = Program.RhsTuple.init(self.allocator);
    errdefer tuple.deinit();
    while (true) {
        const item = self.parseTupleItem(variable_interner) catch |err| switch (err) {
            ParseError.UnexpectedToken => break,
            ParseError.UnexpectedEOF => break,
            else => return err,
        };
        try tuple.items.append(item);
    }
    return tuple;
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
    var result = Program.Lhs.init(self.allocator);
    errdefer result.deinit();
    while (true) {
        const token = self.peek() catch break;
        if (token.type == TokenType.stack_delimiter) {
            try result.items.append(try self.parseLhsItem(variable_interner));
        } else {
            break;
        }
    }
    return result;
}

fn parseRhsItem(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.RHSItem {
    const stack = try self.parseStack();
    const tuple = try self.parseRhsTuple(variable_interner);
    return Program.RHSItem{ .stack = stack, .tuple = tuple };
}

fn parseRhs(self: *Self, variable_interner: *Interner) (Allocator.Error || ParseError)!Program.Rhs {
    var result = Program.Rhs.init(self.allocator);
    errdefer result.deinit();
    while (true) {
        const token = self.peek() catch return result;
        if (token.type == TokenType.stack_delimiter) {
            try result.items.append(try self.parseRhsItem(variable_interner));
        } else {
            break;
        }
    }
    return result;
}

fn parseRule(self: *Self) (Allocator.Error || ParseError)!Program.Rule {
    var rule: Program.Rule = undefined;
    var variable_interner = Interner.init(self.allocator);
    defer variable_interner.deinit();
    try self.match(TokenType.rule_delimiter);
    rule.lhs = try self.parseLhs(&variable_interner);
    errdefer rule.lhs.deinit();
    try self.match(TokenType.rule_delimiter);
    rule.rhs = try self.parseRhs(&variable_interner);
    return rule;
}

fn parseProgram(self: *Self) (Allocator.Error || ParseError)!Program.Program {
    var program = Program.Program.init(self.allocator);
    errdefer program.deinit();
    while (true) {
        const token = try self.peek();
        if (token.type == TokenType.eof) {
            break;
        }
        var rule = try self.parseRule();
        if (rule.isInitial()) {
            try program.appendToInitialState(rule.toOwnedInitialStateItems());
        } else {
            try program.add_rule(rule);
        }
    }
    return program;
}

// the Program is owned by the caller
pub fn parse(self: *Self) (Allocator.Error || ParseError)!Program.Program {
    try self.lexer.lex();
    _ = try self.stack_interner.intern(""); // we intern the "special" stack first
    return self.parseProgram();
}

// TODO: use "initial_state" (or not ?)
// TODO: check that there are no unbound variables on the RHS
// TODO: use toOwnedSline ?
