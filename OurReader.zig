const std = @import("std");
const string = []const u8;
const extras = @import("extras");
const OurReader = @This();
const buf_size = 16;

any: extras.AnyReader,
buf: [buf_size]u8 = std.mem.zeroes([buf_size]u8),
amt: usize = 0,
line: usize = 1,
col: usize = 1,

pub fn eat(ore: *OurReader, comptime test_s: string) !?void {
    if (!try ore.peek(test_s)) return null;
    ore.shiftLAmt(test_s.len);
}

pub fn peek(ore: *OurReader, comptime test_s: string) !bool {
    comptime std.debug.assert(test_s.len > 0);
    comptime std.debug.assert(test_s.len <= buf_size);
    try ore.peekAmt(test_s.len) orelse return false;
    if (test_s.len == 1) return ore.buf[0] == test_s[0];
    return std.mem.eql(u8, test_s, ore.buf[0..test_s.len]);
}

pub fn peekAmt(ore: *OurReader, comptime amt: usize) !?void {
    if (ore.amt >= amt) return;
    const diff_amt = amt - ore.amt;
    const target_buf = ore.buf[ore.amt..][0..diff_amt];
    std.debug.assert(target_buf.len > 0);
    const len = try ore.any.readAll(target_buf);
    if (len == 0) return null;
    for (target_buf) |c| {
        ore.col += 1;
        if (c == '\n') ore.line += 1;
        if (c == '\n') ore.col = 1;
    }
    ore.amt += diff_amt;
}

pub fn shiftLAmt(ore: *OurReader, comptime amt: usize) void {
    std.debug.assert(amt <= ore.amt);
    var new_buf = std.mem.zeroes([buf_size]u8);
    for (amt..ore.amt, 0..) |i, j| new_buf[j] = ore.buf[i];
    ore.buf = new_buf;
    ore.amt -= amt;
}

pub fn skipUntilAfter(ore: *OurReader, comptime test_s: string) !void {
    while (try ore.eat(test_s) == null) {
        ore.shiftLAmt(1);
    }
}

pub fn eatByte(ore: *OurReader, test_c: u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    if (ore.buf[0] == test_c) {
        defer ore.shiftLAmt(1);
        return test_c;
    }
    return null;
}

pub fn eatRange(ore: *OurReader, from: u8, to: u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    if (ore.buf[0] >= from and ore.buf[0] <= to) {
        defer ore.shiftLAmt(1);
        return ore.buf[0];
    }
    return null;
}

pub fn eatAny(ore: *OurReader, comptime test_s: []const u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (ore.buf[0] == c) {
            defer ore.shiftLAmt(1);
            return c;
        }
    }
    return null;
}

pub fn eatAnyNot(ore: *OurReader, test_s: []const u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (ore.buf[0] == c) {
            return null;
        }
    }
    defer ore.shiftLAmt(1);
    return ore.buf[0];
}

pub fn eatQuoteS(ore: *OurReader) !?u8 {
    return ore.eatAny(&.{ '"', '\'' });
}

pub fn eatQuoteE(ore: *OurReader, q: u8) !?void {
    return switch (q) {
        '"' => ore.eat("\""),
        '\'' => ore.eat("'"),
        else => unreachable,
    };
}
