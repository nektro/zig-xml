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
extras: std.ArrayListUnmanaged(u32) = .{},
string_bytes: std.ArrayListUnmanaged(u8) = .{},
strings_map: std.StringArrayHashMapUnmanaged(xml.StringIndex) = .{},
gentity_map: std.AutoArrayHashMapUnmanaged(xml.StringIndex, xml.StringIndex) = .{},
pentity_map: std.AutoArrayHashMapUnmanaged(xml.StringIndex, xml.StringIndex) = .{},
nodes: std.MultiArrayList(Node) = .{},

pub fn eat(ore: *Parser, comptime test_s: string) !?void {
    if (!try ore.peek(test_s)) return null;
    ore.shiftLAmt(test_s.len);
}

pub fn peek(ore: *Parser, comptime test_s: string) !bool {
    comptime std.debug.assert(test_s.len > 0);
    comptime std.debug.assert(test_s.len <= buf_size);
    try ore.peekAmt(test_s.len) orelse return false;
    if (test_s.len == 1) return ore.buf[0] == test_s[0];
    return std.mem.eql(u8, test_s, ore.buf[0..test_s.len]);
}

pub fn peekAmt(ore: *Parser, comptime amt: usize) !?void {
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

pub fn shiftLAmt(ore: *Parser, amt: usize) void {
    std.debug.assert(amt <= ore.amt);
    var new_buf = std.mem.zeroes([buf_size]u8);
    for (amt..ore.amt, 0..) |i, j| new_buf[j] = ore.buf[i];
    ore.buf = new_buf;
    ore.amt -= amt;
}

pub fn eatByte(ore: *Parser, test_c: u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    if (ore.buf[0] == test_c) {
        defer ore.shiftLAmt(1);
        return test_c;
    }
    return null;
}

pub fn eatRange(ore: *Parser, comptime from: u8, comptime to: u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    if (ore.buf[0] >= from and ore.buf[0] <= to) {
        defer ore.shiftLAmt(1);
        return ore.buf[0];
    }
    return null;
}

pub fn eatRangeM(ore: *Parser, comptime from: u21, comptime to: u21) !?u21 {
    const from_len = comptime std.unicode.utf8CodepointSequenceLength(from) catch unreachable;
    const to_len = comptime std.unicode.utf8CodepointSequenceLength(to) catch unreachable;
    const amt = @max(from_len, to_len);
    try ore.peekAmt(amt) orelse return null;
    const len = std.unicode.utf8ByteSequenceLength(ore.buf[0]) catch return null;
    if (amt != len) return null;
    const mcp = std.unicode.utf8Decode(ore.buf[0..amt]) catch return null;
    if (mcp >= from and mcp <= to) {
        defer ore.shiftLAmt(len);
        return @intCast(mcp);
    }
    return null;
}

pub fn eatAny(ore: *Parser, test_s: []const u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (ore.buf[0] == c) {
            defer ore.shiftLAmt(1);
            return c;
        }
    }
    return null;
}

pub fn eatAnyNot(ore: *Parser, test_s: []const u8) !?u8 {
    try ore.peekAmt(1) orelse return null;
    for (test_s) |c| {
        if (ore.buf[0] == c) {
            return null;
        }
    }
    defer ore.shiftLAmt(1);
    return ore.buf[0];
}

pub fn eatQuoteS(ore: *Parser) !?u8 {
    return ore.eatAny(&.{ '"', '\'' });
}

pub fn eatQuoteE(ore: *Parser, q: u8) !?void {
    return switch (q) {
        '"' => ore.eat("\""),
        '\'' => ore.eat("'"),
        else => unreachable,
    };
}

pub fn eatEnum(ore: *Parser, comptime E: type) !?E {
    inline for (comptime std.meta.fieldNames(E)) |name| {
        if (try ore.eat(name)) |_| {
            return @field(E, name);
        }
    }
    return null;
}

pub fn eatEnumU8(ore: *Parser, comptime E: type) !?E {
    inline for (comptime std.meta.fieldNames(E)) |name| {
        if (try ore.eatByte(@intFromEnum(@field(E, name)))) |_| {
            return @field(E, name);
        }
    }
    return null;
}

pub fn addStr(ore: *Parser, alloc: std.mem.Allocator, str: string) !xml.StringIndex {
    const adapter: Adapter = .{ .ore = ore };
    const res = try ore.strings_map.getOrPutAdapted(alloc, str, adapter);
    if (res.found_existing) return res.value_ptr.*;
    const q = ore.string_bytes.items.len;
    try ore.string_bytes.appendSlice(alloc, str);
    const r = ore.extras.items.len;
    try ore.extras.appendSlice(alloc, &[_]u32{ @as(u32, @intCast(q)), @as(u32, @intCast(str.len)) });
    res.value_ptr.* = @enumFromInt(r);
    return @enumFromInt(r);
}

const Adapter = struct {
    ore: *const Parser,

    pub fn hash(ctx: @This(), a: string) u32 {
        _ = ctx;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(a);
        return @truncate(hasher.final());
    }

    pub fn eql(ctx: @This(), a: string, _: string, b_index: usize) bool {
        const sidx = ctx.ore.strings_map.values()[b_index];
        const b = ctx.ore.getStr(sidx);
        return std.mem.eql(u8, a, b);
    }
};

pub fn addStrList(ore: *Parser, alloc: std.mem.Allocator, items: []const xml.StringIndex) !xml.StringListIndex {
    if (items.len == 0) return .empty;
    const r = ore.extras.items.len;
    try ore.extras.ensureUnusedCapacity(alloc, 1 + items.len);
    ore.extras.appendAssumeCapacity(@intCast(items.len));
    ore.extras.appendSliceAssumeCapacity(@ptrCast(items));
    return @enumFromInt(r);
}

pub fn getStr(ore: *const Parser, sidx: xml.StringIndex) string {
    const obj = ore.extras.items[@intFromEnum(sidx)..][0..2].*;
    const str = ore.string_bytes.items[obj[0]..][0..obj[1]];
    return str;
}

pub fn addElemNode(ore: *Parser, alloc: std.mem.Allocator, ele: xml.Element) !xml.NodeIndex {
    const r = ore.nodes.len;
    try ore.nodes.append(alloc, .{ .element = ele });
    return @enumFromInt(r);
}

pub fn addTextNode(ore: *Parser, alloc: std.mem.Allocator, txt: xml.StringIndex) !xml.NodeIndex {
    const r = ore.nodes.len;
    try ore.nodes.append(alloc, .{ .text = txt });
    return @enumFromInt(r);
}

pub fn addPINode(ore: *Parser, alloc: std.mem.Allocator, pi: xml.ProcessingInstruction) !xml.NodeIndex {
    const r = ore.nodes.len;
    try ore.nodes.append(alloc, .{ .pi = pi });
    return @enumFromInt(r);
}

pub const Node = union(enum) {
    text: xml.StringIndex,
    element: xml.Element,
    pi: xml.ProcessingInstruction,
};

pub fn addNodeList(ore: *Parser, alloc: std.mem.Allocator, items: []const xml.NodeIndex) !xml.NodeListIndex {
    if (items.len == 0) return .empty;
    const r = ore.extras.items.len;
    try ore.extras.ensureUnusedCapacity(alloc, 1 + items.len);
    ore.extras.appendAssumeCapacity(@intCast(items.len));
    ore.extras.appendSliceAssumeCapacity(@ptrCast(items));
    return @enumFromInt(r);
}
