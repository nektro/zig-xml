const std = @import("std");
const string = []const u8;
const xml = @import("xml");

pub fn main() !void {
    const path = std.mem.sliceTo(std.os.argv[1], 0);
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var timer = try std.time.Timer.start();
    var doc = try xml.parse(std.heap.c_allocator, path, file.reader());
    defer doc.deinit();
    std.log.warn("{d}ms", .{timer.read() / std.time.ns_per_ms});
}
