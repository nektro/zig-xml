const std = @import("std");
const string = []const u8;
const extras = @import("extras");
const Parser = @This();
const buf_size = 16;
const xml = @import("./mod.zig");

any: extras.AnyReader,
buf: [buf_size]u8 = std.mem.zeroes([buf_size]u8),
amt: usize = 0,
line: usize = 1,
col: usize = 1,
data: std.ArrayListUnmanaged(u32) = .{},
string_bytes: std.ArrayListUnmanaged(u8) = .{},
strings_map: std.StringArrayHashMapUnmanaged(xml.StringIndex) = .{},
gentity_map: std.AutoArrayHashMapUnmanaged(xml.StringIndex, xml.StringIndex) = .{},
pentity_map: std.AutoArrayHashMapUnmanaged(xml.StringIndex, xml.StringIndex) = .{},
nodes: std.MultiArrayList(Node) = .{},

pub fn eat(p: *Parser, comptime test_s: string) !?void {
    if (!try p.peek(test_s)) return null;
    p.shiftLAmt(test_s.len);
}

pub fn peek(p: *Parser, comptime test_s: string) !bool {
    comptime std.debug.assert(test_s.len > 0);
    comptime std.debug.assert(test_s.len <= buf_size);
    try p.peekAmt(test_s.len) orelse return false;
    if (test_s.len == 1) return p.buf[0] == test_s[0];
    return std.mem.eql(u8, test_s, p.buf[0..test_s.len]);
}

pub fn peekAmt(p: *Parser, comptime amt: usize) !?void {
    if (p.amt >= amt) return;
    const diff_amt = amt - p.amt;
    const target_buf = p.buf[p.amt..][0..diff_amt];
    std.debug.assert(target_buf.len > 0);
    const len = try p.any.readAll(target_buf);
    if (len == 0) return null;
    for (target_buf) |c| {
        p.col += 1;
        if (c == '\n') p.line += 1;
        if (c == '\n') p.col = 1;
    }
    p.amt += diff_amt;
}

pub fn shiftLAmt(p: *Parser, amt: usize) void {
    std.debug.assert(amt <= p.amt);
    var new_buf = std.mem.zeroes([buf_size]u8);
    for (amt..p.amt, 0..) |i, j| new_buf[j] = p.buf[i];
    p.buf = new_buf;
    p.amt -= amt;
}

pub fn eatByte(p: *Parser, test_c: u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    if (p.buf[0] == test_c) {
        defer p.shiftLAmt(1);
        return test_c;
    }
    return null;
}

pub fn eatRange(p: *Parser, comptime from: u8, comptime to: u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    if (p.buf[0] >= from and p.buf[0] <= to) {
        defer p.shiftLAmt(1);
        return p.buf[0];
    }
    return null;
}

pub fn eatRangeM(p: *Parser, comptime from: u21, comptime to: u21) !?u21 {
    const from_len = comptime std.unicode.utf8CodepointSequenceLength(from) catch unreachable;
    const to_len = comptime std.unicode.utf8CodepointSequenceLength(to) catch unreachable;
    const amt = @max(from_len, to_len);
    try p.peekAmt(amt) orelse return null;
    const len = std.unicode.utf8ByteSequenceLength(p.buf[0]) catch return null;
    if (amt != len) return null;
    const mcp = std.unicode.utf8Decode(p.buf[0..amt]) catch return null;
    if (mcp >= from and mcp <= to) {
        defer p.shiftLAmt(len);
        return @intCast(mcp);
    }
    return null;
}

pub fn eatAny(p: *Parser, test_s: []const u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (p.buf[0] == c) {
            defer p.shiftLAmt(1);
            return c;
        }
    }
    return null;
}

pub fn eatAnyNot(p: *Parser, test_s: []const u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (p.buf[0] == c) {
            return null;
        }
    }
    defer p.shiftLAmt(1);
    return p.buf[0];
}

pub fn eatQuoteS(p: *Parser) !?u8 {
    return p.eatAny(&.{ '"', '\'' });
}

pub fn eatQuoteE(p: *Parser, q: u8) !?void {
    return switch (q) {
        '"' => p.eat("\""),
        '\'' => p.eat("'"),
        else => unreachable,
    };
}

pub fn eatEnum(p: *Parser, comptime E: type) !?E {
    inline for (comptime std.meta.fieldNames(E)) |name| {
        if (try p.eat(name)) |_| {
            return @field(E, name);
        }
    }
    return null;
}

pub fn eatEnumU8(p: *Parser, comptime E: type) !?E {
    inline for (comptime std.meta.fieldNames(E)) |name| {
        if (try p.eatByte(@intFromEnum(@field(E, name)))) |_| {
            return @field(E, name);
        }
    }
    return null;
}

pub fn addStr(p: *Parser, alloc: std.mem.Allocator, str: string) !xml.StringIndex {
    const adapter: Adapter = .{ .p = p };
    const res = try p.strings_map.getOrPutAdapted(alloc, str, adapter);
    if (res.found_existing) return res.value_ptr.*;
    const q = p.string_bytes.items.len;
    try p.string_bytes.appendSlice(alloc, str);
    const r = p.data.items.len;
    try p.data.appendSlice(alloc, &[_]u32{ @as(u32, @intCast(q)), @as(u32, @intCast(str.len)) });
    res.value_ptr.* = @enumFromInt(r);
    return @enumFromInt(r);
}

const Adapter = struct {
    p: *const Parser,

    pub fn hash(ctx: @This(), a: string) u32 {
        _ = ctx;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(a);
        return @truncate(hasher.final());
    }

    pub fn eql(ctx: @This(), a: string, _: string, b_index: usize) bool {
        const sidx = ctx.p.strings_map.values()[b_index];
        const b = ctx.p.getStr(sidx);
        return std.mem.eql(u8, a, b);
    }
};

pub fn addStrList(p: *Parser, alloc: std.mem.Allocator, items: []const xml.StringIndex) !xml.StringListIndex {
    if (items.len == 0) return .empty;
    const r = p.data.items.len;
    try p.data.ensureUnusedCapacity(alloc, 1 + items.len);
    p.data.appendAssumeCapacity(@intCast(items.len));
    p.data.appendSliceAssumeCapacity(@ptrCast(items));
    return @enumFromInt(r);
}

pub fn getStr(p: *const Parser, sidx: xml.StringIndex) string {
    const obj = p.data.items[@intFromEnum(sidx)..][0..2].*;
    const str = p.string_bytes.items[obj[0]..][0..obj[1]];
    return str;
}

pub fn addElemNode(p: *Parser, alloc: std.mem.Allocator, ele: xml.Element) !xml.NodeIndex {
    const r = p.nodes.len;
    try p.nodes.append(alloc, .{ .element = ele });
    return @enumFromInt(r);
}

pub fn addTextNode(p: *Parser, alloc: std.mem.Allocator, txt: xml.StringIndex) !xml.NodeIndex {
    const r = p.nodes.len;
    try p.nodes.append(alloc, .{ .text = txt });
    return @enumFromInt(r);
}

pub fn addPINode(p: *Parser, alloc: std.mem.Allocator, pi: xml.ProcessingInstruction) !xml.NodeIndex {
    const r = p.nodes.len;
    try p.nodes.append(alloc, .{ .pi = pi });
    return @enumFromInt(r);
}

pub const Node = union(enum) {
    text: xml.StringIndex,
    element: xml.Element,
    pi: xml.ProcessingInstruction,
};

pub fn addNodeList(p: *Parser, alloc: std.mem.Allocator, items: []const xml.NodeIndex) !xml.NodeListIndex {
    if (items.len == 0) return .empty;
    const r = p.data.items.len;
    try p.data.ensureUnusedCapacity(alloc, 1 + items.len);
    p.data.appendAssumeCapacity(@intCast(items.len));
    p.data.appendSliceAssumeCapacity(@ptrCast(items));
    return @enumFromInt(r);
}
