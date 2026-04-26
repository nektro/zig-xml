const std = @import("std");
const string = []const u8;
const xml = @import("xml");
const time = @import("time");

pub fn main() !void {
    const path = std.mem.sliceTo(std.os.argv[1], 0);
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const start = time.nanoTimestamp();
    var doc = try xml.parse(std.heap.c_allocator, path, file.reader());
    defer doc.deinit();
    std.log.warn("{d}ms", .{(time.nanoTimestamp() - start) / time.ns_per_ms});
}
