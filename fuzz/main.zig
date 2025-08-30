const std = @import("std");
const xml = @import("xml");
const nfs = @import("nfs");

pub export fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const stdin = nfs.stdin();

    var doc = xml.parse(allocator, "input.xml", stdin) catch return;
    defer doc.deinit();
}
