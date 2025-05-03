const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

pub const LexerError = error{
    EOFError,
};

pub const TokenType = enum {
    rule_delimiter,
    stack_delimiter,
    question_mark,
    identifier,
    variable,
};

pub const Token = struct {
    type: TokenType,
    pos: usize,
    val: []const u8,
};

source: []const u8,
start: usize,
pos: usize,
rule_delimiter: u8,
stack_delimiter: u8,
tokens: std.ArrayList(Token),

pub fn init(allocator: Allocator, source: []const u8) Self {
    return Self{
        .source = source,
        .start = 0,
        .pos = 0,
        .rule_delimiter = 0,
        .stack_delimiter = 0,
        .tokens = std.ArrayList(Token).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.tokens.deinit();
}

fn isEof(self: Self) bool {
    return self.pos >= self.source.len;
}

fn advance(self: *Self) void {
    if (!self.isEof())
        self.pos += 1;
}

fn peek(self: *Self) ?u8 {
    if (self.isEof()) {
        return null;
    } else {
        return self.source[self.pos];
    }
}

fn readChar(self: *Self) ?u8 {
    if (self.isEof()) {
        return null;
    } else {
        const result = self.source[self.pos];
        self.advance();
        return result;
    }
}

fn skip_space(self: *Self) void {
    while (!self.isEof() and std.ascii.isWhitespace(self.source[self.pos])) {
        self.pos += 1;
    }
}

fn newToken(self: *Self) void {
    self.skip_space();
    self.start = self.pos;
}

fn append(self: *Self, typ: TokenType) Allocator.Error!void {
    try self.tokens.append(Token{ .type = typ, .pos = self.start, .val = self.source[self.start..self.pos] });
}

fn identifier(self: *Self) void {
    while (true) {
        if (self.peek()) |c| {
            if (std.ascii.isWhitespace(c) or c == self.rule_delimiter or c == self.stack_delimiter or c == '?') {
                break;
            }
            self.advance();
        } else {
            break;
        }
    }
}

pub fn lex(self: *Self) Allocator.Error!void {
    self.newToken();
    if (self.readChar()) |c| {
        self.rule_delimiter = c;
        try self.append(TokenType.rule_delimiter);
    } else {
        return;
    }
    self.newToken();
    if (self.readChar()) |c| {
        self.stack_delimiter = c;
        try self.append(TokenType.stack_delimiter);
    } else {
        return;
    }
    while (true) {
        self.newToken();
        if (self.readChar()) |c| {
            if (c == self.rule_delimiter) {
                try self.append(TokenType.rule_delimiter);
            } else if (c == self.stack_delimiter) {
                try self.append(TokenType.stack_delimiter);
            } else if (c == '?') {
                try self.append(TokenType.question_mark);
            } else if (c == '$') {
                self.advance();
                self.identifier();
                try self.append(TokenType.variable);
            } else {
                self.identifier();
                try self.append(TokenType.identifier);
            }
        } else {
            break;
        }
    }
}

pub fn get(self: Self, i: usize) LexerError!Token {
    if (i < self.tokens.items.len) {
        return self.tokens.items[i];
    } else {
        return LexerError.EOFError;
    }
}
