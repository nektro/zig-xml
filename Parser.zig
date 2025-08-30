const std = @import("std");
const string = []const u8;
const Parser = @This();
const xml = @import("./mod.zig");
const nio = @import("nio");

any: nio.AnyReadable,
allocator: std.mem.Allocator,
temp: std.ArrayListUnmanaged(u8) = .{},
idx: usize = 0,
end: bool = false,
data: std.ArrayListUnmanaged(u32) = .{},
string_bytes: std.ArrayListUnmanaged(u8) = .{},
strings_map: std.StringArrayHashMapUnmanaged(xml.StringIndex) = .{},
gentity_map: std.AutoArrayHashMapUnmanaged(xml.StringIndex, xml.StringIndex) = .{},
pentity_map: std.AutoArrayHashMapUnmanaged(xml.StringIndex, xml.StringIndex) = .{},
nodes: std.MultiArrayList(Node) = .{},

pub fn avail(p: *Parser) usize {
    return p.temp.items.len - p.idx;
}

pub fn slice(p: *Parser) []const u8 {
    return p.temp.items[p.idx..];
}

pub fn eat(p: *Parser, comptime test_s: string) !?void {
    if (!try p.peek(test_s)) return null;
    p.idx += test_s.len;
}

pub fn peek(p: *Parser, comptime test_s: string) !bool {
    try p.peekAmt(test_s.len) orelse return false;
    if (test_s.len == 1) return p.slice()[0] == test_s[0];
    return std.mem.eql(u8, test_s, p.slice()[0..test_s.len]);
}

pub fn peekAmt(p: *Parser, comptime amt: usize) !?void {
    if (p.avail() >= amt) return;
    if (p.end) return null;
    const buf_size = std.heap.page_size_min;
    const diff_amt = amt - p.avail();
    std.debug.assert(diff_amt <= buf_size);
    var buf: [buf_size]u8 = undefined;
    const len = try p.any.readAll(&buf);
    if (len == 0) p.end = true;
    if (len == 0) return null;
    try p.temp.appendSlice(p.allocator, buf[0..len]);
    if (amt > len) return null;
}

pub fn eatByte(p: *Parser, test_c: u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    if (p.slice()[0] == test_c) {
        defer p.idx += 1;
        return test_c;
    }
    return null;
}

pub fn eatRange(p: *Parser, comptime from: u8, comptime to: u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    if (p.slice()[0] >= from and p.slice()[0] <= to) {
        defer p.idx += 1;
        return p.slice()[0];
    }
    return null;
}

pub fn eatRangeM(p: *Parser, comptime from: u21, comptime to: u21) !?u21 {
    const from_len = comptime std.unicode.utf8CodepointSequenceLength(from) catch unreachable;
    const to_len = comptime std.unicode.utf8CodepointSequenceLength(to) catch unreachable;
    const amt = @max(from_len, to_len);
    try p.peekAmt(amt) orelse return null;
    const len = std.unicode.utf8ByteSequenceLength(p.slice()[0]) catch return null;
    if (amt != len) return null;
    const mcp = std.unicode.utf8Decode(p.slice()[0..amt]) catch return null;
    if (mcp >= from and mcp <= to) {
        defer p.idx += len;
        return @intCast(mcp);
    }
    return null;
}

pub fn eatAny(p: *Parser, test_s: []const u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (p.slice()[0] == c) {
            defer p.idx += 1;
            return c;
        }
    }
    return null;
}

pub fn eatAnyNot(p: *Parser, test_s: []const u8) !?u8 {
    try p.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (p.slice()[0] == c) {
            return null;
        }
    }
    defer p.idx += 1;
    return p.slice()[0];
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
