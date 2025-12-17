const std = @import("std");
const string = []const u8;
const xml = @import("xml");
const expect = std.testing.expect;
const nfs = @import("nfs");
const nio = @import("nio");

// zig fmt: off
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/001.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/002.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/003.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/004.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/005.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/006.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/007.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/008.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/009.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/010.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/011.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/012.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/013.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/014.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/015.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/016.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/017.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/018.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/019.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/020.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/021.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/022.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/023.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/024.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/025.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/026.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/027.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/028.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/029.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/030.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/031.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/032.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/033.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/034.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/035.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/036.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/037.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/038.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/039.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/040.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/041.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/042.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/043.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/044.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/045.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/046.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/047.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/048.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/049.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/050.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/051.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/052.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/053.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/054.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/055.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/056.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/057.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/058.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/059.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/060.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/061.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/062.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/063.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/064.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/065.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/066.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/067.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/068.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/069.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/070.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/071.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/072.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/073.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/074.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/075.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/076.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/077.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/078.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/079.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/080.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/081.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/082.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/083.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/084.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/085.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/086.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/087.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/088.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/089.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/090.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/091.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/092.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/093.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/094.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/095.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/096.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/097.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/098.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/099.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/100.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/101.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/102.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/103.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/104.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/105.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/106.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/107.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/108.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/109.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/110.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/111.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/112.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/113.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/114.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/115.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/116.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/117.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/118.xml"); }
test { try doValid("xml-test-suite/xmlconf/xmltest/valid/sa/119.xml"); }
// zig fmt: on

fn doValid(testfile_path: [:0]const u8) !void {
    var testfile_file = try nfs.cwd().openFile(testfile_path, .{});
    defer testfile_file.close();
    var doc = try xml.parse(std.testing.allocator, testfile_path, &testfile_file);
    defer doc.deinit();
}

test {
    const input =
        \\<?xml version="1.0" standalone="yes" ?>
        \\<category name="Technology">
        \\  <book title="Learning Amazon Web Services" author="Mark Wilkins">
        \\    <price>$20</price>
        \\  </book>
        \\  <book title="The Hunger Games" author="Suzanne Collins">
        \\    <price>$13</price>
        \\  </book>
        \\  <book title="The Lightning Thief: Percy Jackson and the Olympians" author="Rick Riordan"></book>
        \\</category>
    ;
    var fbs = nio.FixedBufferStream([]const u8).init(input);
    var doc = try xml.parse(std.testing.allocator, "<stdin>", &fbs);
    defer doc.deinit();
    doc.acquire();
    defer doc.release();

    try expectEqualStrings(doc.root.tag_name.slice(), "category");

    const children = doc.root.children();
    try expect(children.len == 3);
    try expect(children[0].v() == .element);
    try expect(children[1].v() == .element);
    try expect(children[2].v() == .element);

    const child1 = children[1].v().element;
    try expectEqualStrings(child1.tag_name.slice(), "book");
    try expectEqualStrings(child1.attr("title").?, "The Hunger Games");

    const children2 = child1.children();
    try expect(children2.len == 1);
    try expect(children2[0].v() == .element);

    const child2 = children2[0].v().element;
    try expectEqualStrings(child2.tag_name.slice(), "price");
    const children3 = child2.children();
    try expect(children3.len == 1);
    try expect(children3[0].v() == .text);
    try expectEqualStrings(children3[0].v().text.slice(), "$13");
}

fn expectEqualStrings(actual: []const u8, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, actual);
}
