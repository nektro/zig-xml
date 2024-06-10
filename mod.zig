//! Parser for Extensible Markup Language (XML)
//! https://www.w3.org/TR/xml/
// https://www.w3.org/XML/Test/xmlconf-20020606.htm

const std = @import("std");
const string = []const u8;
const Parser = @import("./Parser.zig");
const log = std.log.scoped(.xml);
const tracer = @import("tracer");

//
//

pub fn parse(alloc: std.mem.Allocator, path: string, inreader: anytype) !Document {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var bufread = std.io.bufferedReader(inreader);
    var counter = std.io.countingReader(bufread.reader());
    var ourreader = Parser{ .any = counter.reader().any() };
    errdefer ourreader.data.deinit(alloc);
    errdefer ourreader.string_bytes.deinit(alloc);
    errdefer ourreader.strings_map.deinit(alloc);
    defer ourreader.gentity_map.deinit(alloc);
    defer ourreader.pentity_map.deinit(alloc);
    errdefer ourreader.nodes.deinit(alloc);

    _ = try ourreader.addStr(alloc, "");
    return parseDocument(alloc, &ourreader) catch |err| switch (err) {
        error.XmlMalformed => {
            log.err("{s}:{d}:{d}: {d}'{s}'", .{ path, ourreader.line, ourreader.col -| ourreader.amt, ourreader.amt, ourreader.buf });
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
            return err;
        },
        // stave off error: error sets 'anyerror' and 'error{}' have no common errors
        else => |e| @as(@TypeOf(counter.reader()).Error || error{XmlMalformed}, @errorCast(e)),
    };
}

/// document   ::=   prolog element Misc*
fn parseDocument(alloc: std.mem.Allocator, p: *Parser) anyerror!Document {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    _ = try parseProlog(alloc, p) orelse return error.XmlMalformed;
    const root = try parseElement(alloc, p) orelse return error.XmlMalformed;
    while (true) _ = try parseMisc(alloc, p) orelse break;

    defer p.strings_map.deinit(alloc);
    return .{
        .allocator = alloc,
        .data = try p.data.toOwnedSlice(alloc),
        .string_bytes = try p.string_bytes.toOwnedSlice(alloc),
        .nodes = p.nodes.toOwnedSlice(),
        .root = root,
    };
}

/// prolog   ::=   XMLDecl? Misc* (doctypedecl Misc*)?
fn parseProlog(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    _ = try parseXMLDecl(alloc, p) orelse {};
    while (true) _ = try parseMisc(alloc, p) orelse break;
    try parseDoctypeDecl(alloc, p) orelse return;
    while (true) _ = try parseMisc(alloc, p) orelse break;
}

/// element   ::=   EmptyElemTag
/// element   ::=   STag content ETag
///
/// EmptyElemTag   ::=   '<' Name (S Attribute)* S? '/>'
/// STag           ::=   '<' Name (S Attribute)* S? '>'
fn parseElement(alloc: std.mem.Allocator, p: *Parser) anyerror!?Element {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.peek("</")) return null;
    if (try p.peek("<!")) return null;
    try p.eat("<") orelse return null;
    const name = try parseName(alloc, p) orelse return error.XmlMalformed;
    const attributes = try collectAttributes(alloc, p);
    try parseS(p) orelse {};
    if (try p.eat("/>")) |_| return .{
        .tag_name = name,
        .attributes = attributes,
        .content = null,
    };
    try p.eat(">") orelse return error.XmlMalformed;

    const content = try parseContent(alloc, p) orelse return error.XmlMalformed;
    try parseETag(alloc, p, name) orelse return error.XmlMalformed;
    return .{
        .tag_name = name,
        .attributes = attributes,
        .content = content,
    };
}

fn collectAttributes(alloc: std.mem.Allocator, p: *Parser) !AttributeListIndex {
    var list = std.ArrayList(StringIndex).init(alloc);
    defer list.deinit();

    while (true) {
        try parseS(p) orelse {};
        const attr = try parseAttribute(alloc, p) orelse break;
        try list.append(attr.name);
        try list.append(attr.value);
    }
    return @enumFromInt(@intFromEnum(try p.addStrList(alloc, list.items)));
}

/// Misc   ::=   Comment | PI | S
fn parseMisc(alloc: std.mem.Allocator, p: *Parser) anyerror!?Misc {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parseComment(p)) |_| return .{ .comment = {} };
    if (try parsePI(alloc, p)) |pi| return .{ .pi = pi };
    if (try parseS(p)) |_| return .{ .s = {} };
    return null;
}

/// XMLDecl   ::=   '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'
fn parseXMLDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?XMLDecl {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<?xml") orelse return null;
    const version_info = try parseVersionInfo(p) orelse return error.XmlMalformed;
    const encoding = try parseEncodingDecl(alloc, p);
    const standalone = try parseSDDecl(p) orelse .no;
    try parseS(p) orelse {};
    try p.eat("?>") orelse return error.XmlMalformed;
    if (version_info[0] != 1) return error.XmlMalformed; // version should be 1.0
    if (version_info[1] != 0) return error.XmlMalformed; // version should be 1.0
    return .{
        .encoding = encoding,
        .standalone = standalone,
    };
}

/// doctypedecl   ::=   '<!DOCTYPE' S Name (S ExternalID)? S? ('[' intSubset ']' S?)? '>'
fn parseDoctypeDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<!DOCTYPE") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    _ = try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse {};
    _ = try parseExternalOrPublicID(alloc, p, false) orelse {};
    try parseS(p) orelse {};
    if (try p.eat("[")) |_| {
        try parseIntSubset(alloc, p) orelse return error.XmlMalformed;
        try p.eat("]") orelse return error.XmlMalformed;
        try parseS(p) orelse {};
    }
    try p.eat(">") orelse return error.XmlMalformed;
}

/// content   ::=   CharData? ((element | Reference | CDSect | PI | Comment) CharData?)*
fn parseContent(alloc: std.mem.Allocator, p: *Parser) anyerror!?NodeListIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list1 = std.ArrayList(NodeIndex).init(alloc);
    defer list1.deinit();
    var list2 = std.ArrayList(u8).init(alloc);
    defer list2.deinit();

    try addOpStringToList(p, &list2, try parseCharData(alloc, p));
    while (true) {
        if (try parsePI(alloc, p)) |pi| {
            try list1.append(try p.addPINode(alloc, pi));
            if (list2.items.len > 0) {
                try list1.append(try p.addTextNode(alloc, try p.addStr(alloc, list2.items)));
                list2.clearRetainingCapacity();
            }
            try addOpStringToList(p, &list2, try parseCharData(alloc, p));
            continue;
        }
        if (try parseElement(alloc, p)) |elem| {
            try list1.append(try p.addElemNode(alloc, elem));
            if (list2.items.len > 0) {
                try list1.append(try p.addTextNode(alloc, try p.addStr(alloc, list2.items)));
                list2.clearRetainingCapacity();
            }
            try addOpStringToList(p, &list2, try parseCharData(alloc, p));
            continue;
        }
        if (try parseReference(alloc, p)) |ref| {
            try addReferenceToList(p, &list2, ref);
            try addOpStringToList(p, &list2, try parseCharData(alloc, p));
            continue;
        }
        if (try parseCDSect(alloc, p)) |cdata| {
            try addOpStringToList(p, &list2, cdata);
            try addOpStringToList(p, &list2, try parseCharData(alloc, p));
            continue;
        }
        if (try parseComment(p)) |_| {
            try addOpStringToList(p, &list2, try parseCharData(alloc, p));
            continue;
        }
        break;
    }
    if (list2.items.len > 0) {
        try list1.append(try p.addTextNode(alloc, try p.addStr(alloc, list2.items)));
        list2.clearRetainingCapacity();
    }
    return try p.addNodeList(alloc, list1.items);
}

/// ETag   ::=   '</' Name S? '>'
fn parseETag(alloc: std.mem.Allocator, p: *Parser, expected_name: StringIndex) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("</") orelse return null;
    const name = try parseName(alloc, p) orelse return error.XmlMalformed;
    if (name != expected_name) return error.XmlMalformed;
    try parseS(p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// Comment   ::=   '<!--' ((Char - '-') | ('-' (Char - '-')))* '-->'
fn parseComment(p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<!--") orelse return null;
    while (true) {
        if (try p.eat("-->")) |_| break;
        _ = try parseChar(p) orelse return error.XmlMalformed;
    }
}

/// PI   ::=   '<?' PITarget (S (Char* - (Char* '?>' Char*)))? '?>'
fn parsePI(alloc: std.mem.Allocator, p: *Parser) anyerror!?ProcessingInstruction {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<?") orelse return null;
    const target = try parsePITarget(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse {};

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();
    while (true) {
        if (try p.eat("?>")) |_| break;
        const cp = try parseChar(p) orelse return error.XmlMalformed;
        try addUCPtoList(&list, cp);
    }
    return .{
        .target = target,
        .rest = try p.addStr(alloc, list.items),
    };
}

/// S   ::=   (#x20 | #x9 | #xD | #xA)+
fn parseS(p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.eatAny(&.{ 0x20, 0x09, 0x0D, 0x0A })) |_| continue; // space, \t, \r, \n
        if (i == 0) return null;
        break;
    }
}

/// VersionInfo   ::=   S 'version' Eq ("'" VersionNum "'" | '"' VersionNum '"')
fn parseVersionInfo(p: *Parser) anyerror!?[2]u8 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseS(p) orelse return null;
    try p.eat("version") orelse return error.XmlMalformed;
    try parseEq(p) orelse return error.XmlMalformed;
    const q = try p.eatQuoteS() orelse return error.XmlMalformed;
    const vers = try parseVersionNum(p) orelse return error.XmlMalformed;
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
    return vers;
}

/// EncodingDecl   ::=   S 'encoding' Eq ('"' EncName '"' | "'" EncName "'" )
fn parseEncodingDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseS(p) orelse {};
    try p.eat("encoding") orelse return null;
    try parseEq(p) orelse return error.XmlMalformed;
    const q = try p.eatQuoteS() orelse return error.XmlMalformed;
    const ename = try parseEncName(alloc, p) orelse return error.XmlMalformed;
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
    return ename;
}

/// SDDecl   ::=   S 'standalone' Eq (("'" ('yes' | 'no') "'") | ('"' ('yes' | 'no') '"'))
fn parseSDDecl(p: *Parser) anyerror!?Standalone {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseS(p) orelse {};
    try p.eat("standalone") orelse return null;
    try parseEq(p) orelse return error.XmlMalformed;
    const q = try p.eatQuoteS() orelse return error.XmlMalformed;
    const sd = try p.eatEnum(Standalone) orelse return error.XmlMalformed;
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
    return sd;
}

/// Name   ::=   NameStartChar (NameChar)*
fn parseName(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    try addUCPtoList(&list, try parseNameStartChar(p) orelse return null);
    while (true) {
        try addUCPtoList(&list, try parseNameChar(p) orelse break);
    }
    return try p.addStr(alloc, list.items);
}

/// ExternalID   ::=   'SYSTEM' S SystemLiteral
/// PublicID     ::=   'PUBLIC' S PubidLiteral
/// ExternalID   ::=   'PUBLIC' S PubidLiteral S SystemLiteral
fn parseExternalOrPublicID(alloc: std.mem.Allocator, p: *Parser, comptime allow_public: bool) anyerror!?ID {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("SYSTEM") orelse {
        try p.eat("PUBLIC") orelse return null;
        try parseS(p) orelse return error.XmlMalformed;
        const pubid_lit = try parsePubidLiteral(alloc, p) orelse return error.XmlMalformed;
        try parseS(p) orelse return if (allow_public) .{ .public = pubid_lit } else error.XmlMalformed;
        const sys_lit = try parseSystemLiteral(alloc, p) orelse return error.XmlMalformed;
        return .{ .external = .{ .public = .{ pubid_lit, sys_lit } } };
    };
    try parseS(p) orelse return error.XmlMalformed;
    const sys_lit = try parseSystemLiteral(alloc, p) orelse return error.XmlMalformed;
    return .{ .external = .{ .system = sys_lit } };
}

/// intSubset   ::=   (markupdecl | DeclSep)*
fn parseIntSubset(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var i: usize = 0;
    while (true) : (i += 1) {
        if (try parseMarkupDecl(alloc, p)) |_| continue;
        if (try parseDeclSep(alloc, p)) |_| continue;
        if (i == 0) return null;
        break;
    }
}

/// Attribute   ::=   Name Eq AttValue
fn parseAttribute(alloc: std.mem.Allocator, p: *Parser) anyerror!?Attribute {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    const name = try parseName(alloc, p) orelse return null;
    try parseEq(p) orelse return error.XmlMalformed;
    const value = try parseAttValue(alloc, p) orelse return error.XmlMalformed;
    return .{
        .name = name,
        .value = value,
    };
}

/// CharData   ::=   [^<&]* - ([^<&]* ']]>' [^<&]*)
fn parseCharData(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.peek("]]>")) break;
        if (try p.eatAnyNot("<&")) |c| {
            try list.append(c);
            continue;
        }
        if (i == 0) return null;
        break;
    }
    return try p.addStr(alloc, list.items);
}

/// Reference   ::=   EntityRef | CharRef
fn parseReference(alloc: std.mem.Allocator, p: *Parser) anyerror!?Reference {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    const cp = try parseCharRef(p) orelse {
        const ref = try parseEntityRef(alloc, p) orelse return null;
        const ent = p.gentity_map.get(ref) orelse {
            const actual = p.getStr(ref);
            if (std.mem.eql(u8, actual, "amp")) return .{ .char = '&' };
            if (std.mem.eql(u8, actual, "lt")) return .{ .char = '<' };
            if (std.mem.eql(u8, actual, "gt")) return .{ .char = '>' };
            if (std.mem.eql(u8, actual, "apos")) return .{ .char = '\'' };
            if (std.mem.eql(u8, actual, "quot")) return .{ .char = '"' };
            return .{ .entity_name = ref };
        };
        return .{ .entity_found = ent };
    };
    return .{ .char = cp };
}

/// CDSect   ::=   CDStart CData CDEnd
fn parseCDSect(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseCDStart(p) orelse return null;
    const text = try parseCData(alloc, p) orelse return error.XmlMalformed;
    try parseCDEnd(p) orelse return error.XmlMalformed;
    return text;
}

/// PITarget   ::=   Name - (('X' | 'x') ('M' | 'm') ('L' | 'l'))
fn parsePITarget(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.peek("xml ")) return null;
    if (try p.peek("XML ")) return null;
    return try parseName(alloc, p) orelse return null;
}

/// Char   ::=   #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]	/* any Unicode character, excluding the surrogate blocks, FFFE, and FFFF. */
fn parseChar(p: *Parser) anyerror!?u21 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.peekAmt(3) orelse return null;
    if (std.unicode.utf8Decode(p.buf[0..1]) catch null) |cp| {
        p.shiftLAmt(1);
        return cp;
    }
    if (std.unicode.utf8Decode(p.buf[0..2]) catch null) |cp| {
        p.shiftLAmt(2);
        return cp;
    }
    if (std.unicode.utf8Decode(p.buf[0..3]) catch null) |cp| {
        p.shiftLAmt(3);
        return cp;
    }
    return null;
}

/// Eq   ::=   S? '=' S?
fn parseEq(p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseS(p) orelse {};
    try p.eat("=") orelse return null;
    try parseS(p) orelse {};
}

/// VersionNum   ::=   '1.' [0-9]+
fn parseVersionNum(p: *Parser) anyerror!?[2]u8 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var vers = [2]u8{ 1, 0 };
    try p.eat("1.") orelse return null;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.eatRange('0', '9')) |c| {
            vers[1] *= 10;
            vers[1] += c - '0';
            continue;
        }
        if (i == 0) return null;
        break;
    }
    return vers;
}

/// EncName   ::=   [A-Za-z] ([A-Za-z0-9._] | '-')*
fn parseEncName(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    const b = try p.eatRange('A', 'Z') orelse try p.eatRange('a', 'z') orelse return null;
    try list.append(b);
    while (true) {
        const c = try p.eatRange('A', 'Z') orelse
            try p.eatRange('a', 'z') orelse
            try p.eatRange('0', '9') orelse
            try p.eatByte('.') orelse
            try p.eatByte('_') orelse
            try p.eatByte('-') orelse
            break;
        try list.append(c);
    }
    return try p.addStr(alloc, list.items);
}

/// NameStartChar   ::=   ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
fn parseNameStartChar(p: *Parser) anyerror!?u21 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.eatByte(':')) |b| return b;
    if (try p.eatRange('A', 'Z')) |b| return b;
    if (try p.eatByte('_')) |b| return b;
    if (try p.eatRange('a', 'z')) |b| return b;
    if (try p.eatRangeM(0xC0, 0xD6)) |b| return b;
    if (try p.eatRangeM(0xD8, 0xF6)) |b| return b;
    if (try p.eatRangeM(0xF8, 0x2FF)) |b| return b;
    if (try p.eatRangeM(0x370, 0x37D)) |b| return b;
    if (try p.eatRangeM(0x37F, 0x1FFF)) |b| return b;
    if (try p.eatRangeM(0x200C, 0x200D)) |b| return b;
    if (try p.eatRangeM(0x2070, 0x218F)) |b| return b;
    if (try p.eatRangeM(0x2C00, 0x2FEF)) |b| return b;
    if (try p.eatRangeM(0x3001, 0xD7FF)) |b| return b;
    if (try p.eatRangeM(0xF900, 0xFDCF)) |b| return b;
    if (try p.eatRangeM(0xFDF0, 0xFFFD)) |b| return b;
    if (try p.eatRangeM(0x10000, 0xEFFFF)) |b| return b;
    return null;
}

/// NameChar   ::=   NameStartChar | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
fn parseNameChar(p: *Parser) anyerror!?u21 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.eatByte('-')) |b| return b;
    if (try p.eatByte('.')) |b| return b;
    if (try p.eatRange('0', '9')) |b| return b;
    if (try parseNameStartChar(p)) |b| return b;
    if (try p.eatRangeM(0xB7, 0xB7)) |b| return b;
    if (try p.eatRangeM(0x0300, 0x036F)) |b| return b;
    if (try p.eatRangeM(0x203F, 0x2040)) |b| return b;
    return null;
}

/// SystemLiteral   ::=   ('"' [^"]* '"')
/// SystemLiteral   ::=   ("'" [^']* "'")
fn parseSystemLiteral(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    const q = try p.eatQuoteS() orelse return null;
    while (true) {
        if (try p.eatByte(q)) |_| break;
        try p.peekAmt(1) orelse return error.XmlMalformed;
        const c = try p.eatByte(p.buf[0]) orelse return error.XmlMalformed;
        try list.append(c);
    }
    return try p.addStr(alloc, list.items);
}

/// PubidLiteral   ::=   '"' PubidChar* '"'
/// PubidLiteral   ::=   "'" (PubidChar - "'")* "'"
fn parsePubidLiteral(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    const q = try p.eatQuoteS() orelse return null;
    while (true) {
        if (try p.eatQuoteE(q)) |_| break;
        const c = try parsePubidChar(p) orelse break;
        try addUCPtoList(&list, c);
    }
    return try p.addStr(alloc, list.items);
}

/// markupdecl   ::=   elementdecl | AttlistDecl | EntityDecl | NotationDecl | PI | Comment
fn parseMarkupDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parseElementDecl(alloc, p)) |_| return;
    if (try parseAttlistDecl(alloc, p)) |_| return;
    if (try parseEntityDecl(alloc, p)) |_| return;
    if (try parseNotationDecl(alloc, p)) |_| return;
    if (try parsePI(alloc, p)) |_| return;
    if (try parseComment(p)) |_| return;
    return null;
}

/// DeclSep   ::=   PEReference | S
fn parseDeclSep(alloc: std.mem.Allocator, p: *Parser) anyerror!?DeclSep {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parsePEReference(alloc, p)) |s| return .{ .pe_ref = s };
    if (try parseS(p)) |_| return .{ .s = {} };
    return null;
}

/// AttValue   ::=   '"' ([^<&"] | Reference)* '"'
/// AttValue   ::=   "'" ([^<&'] | Reference)* "'"
fn parseAttValue(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    const q = try p.eatQuoteS() orelse return null;
    while (true) blk: {
        if (try p.eatQuoteE(q)) |_| break;
        if (try p.eatAnyNot(&.{ '<', '&', q })) |b| break :blk try list.append(b);
        if (try parseReference(alloc, p)) |ref| break :blk try addReferenceToList(p, &list, ref);
        unreachable;
    }
    return try p.addStr(alloc, list.items);
}

/// EntityRef   ::=   '&' Name ';'
fn parseEntityRef(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("&") orelse return null;
    const name = try parseName(alloc, p) orelse return error.XmlMalformed;
    try p.eat(";") orelse return error.XmlMalformed;
    return name;
}

/// CharRef   ::=   '&#' [0-9]+ ';'
/// CharRef   ::=   '&#x' [0-9a-fA-F]+ ';'
fn parseCharRef(p: *Parser) anyerror!?u21 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("&#x") orelse {
        try p.eat("&#") orelse return null;
        var i: usize = 0;
        var d: u21 = 0;
        while (true) : (i += 1) {
            if (try p.eatRange('0', '9')) |c| {
                d *= 10;
                d += c - '0';
                continue;
            }
            if (i == 0) return error.XmlMalformed;
            break;
        }
        try p.eat(";") orelse return error.XmlMalformed;
        return d;
    };
    var i: usize = 0;
    var d: u21 = 0;
    while (true) : (i += 1) {
        if (try p.eatRange('0', '9')) |c| {
            d *= 16;
            d += c - '0';
            continue;
        }
        if (try p.eatRange('a', 'f')) |c| {
            d *= 16;
            d += c - 'a' + 10;
            continue;
        }
        if (try p.eatRange('A', 'F')) |c| {
            d *= 16;
            d += c - 'A' + 10;
            continue;
        }
        if (i == 0) return error.XmlMalformed;
        break;
    }
    try p.eat(";") orelse return error.XmlMalformed;
    return d;
}

/// CDStart   ::=   '<![CDATA['
fn parseCDStart(p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<![CDATA[") orelse return null;
}

/// CData   ::=   (Char* - (Char* ']]>' Char*))
fn parseCData(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    while (true) {
        if (try p.peek("]]>")) break;
        const c = try parseChar(p) orelse return error.XmlMalformed;
        try addUCPtoList(&list, c);
    }
    return try p.addStr(alloc, list.items);
}

/// CDEnd   ::=   ']]>'
fn parseCDEnd(p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    return p.eat("]]>");
}

/// PubidChar   ::=   #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
fn parsePubidChar(p: *Parser) anyerror!?u21 {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.eatByte(0x20)) |b| return b; // space
    if (try p.eatByte(0x0D)) |b| return b; // \r
    if (try p.eatByte(0x0A)) |b| return b; // \n
    if (try p.eatRange('a', 'z')) |b| return b;
    if (try p.eatRange('A', 'Z')) |b| return b;
    if (try p.eatRange('0', '9')) |b| return b;
    if (try p.eatAny("-'()+,./:=?;!*#@$_%")) |b| return b;
    return null;
}

/// elementdecl   ::=   '<!ELEMENT' S Name S contentspec S? '>'
fn parseElementDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<!ELEMENT") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    _ = try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse return error.XmlMalformed;
    try parseContentSpec(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// AttlistDecl   ::=   '<!ATTLIST' S Name AttDef* S? '>'
fn parseAttlistDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<!ATTLIST") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    _ = try parseName(alloc, p) orelse return error.XmlMalformed;
    while (true) try parseAttDef(alloc, p) orelse break;
    try parseS(p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// EntityDecl   ::=   GEDecl | PEDecl
fn parseEntityDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?EntityDecl {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<!ENTITY") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    if (try parseGEDecl(alloc, p)) |ge| return .{ .ge = ge };
    if (try parsePEDecl(alloc, p)) |pe| return .{ .pe = pe };
    return null;
}

/// NotationDecl   ::=   '<!NOTATION' S Name S (ExternalID | PublicID) S? '>'
fn parseNotationDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?NotationDecl {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("<!NOTATION") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    const name = try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse return error.XmlMalformed;
    const id = try parseExternalOrPublicID(alloc, p, true) orelse return error.XmlMalformed;
    try parseS(p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
    return .{
        .name = name,
        .id = id,
    };
}

/// PEReference   ::=   '%' Name ';'
fn parsePEReference(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("%") orelse return null;
    const name = try parseName(alloc, p) orelse return error.XmlMalformed;
    try p.eat(";") orelse return error.XmlMalformed;
    return name;
}

/// contentspec   ::=   'EMPTY' | 'ANY' | Mixed | children
fn parseContentSpec(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.eat("EMPTY")) |_| return;
    if (try p.eat("ANY")) |_| return;

    try p.eat("(") orelse return null;
    try parseS(p) orelse {};
    if (try parseMixed(alloc, p)) |_| return;
    if (try parseChildren(alloc, p)) |_| return;
    return null;
}

/// AttDef   ::=   S Name S AttType S DefaultDecl
fn parseAttDef(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseS(p) orelse return null;
    _ = try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse return error.XmlMalformed;
    _ = try parseAttType(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse return error.XmlMalformed;
    try parseDefaultDecl(alloc, p) orelse return error.XmlMalformed;
}

/// GEDecl   ::=   '<!ENTITY' S Name S EntityDef S? '>'
fn parseGEDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?GEDecl {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    const name = try parseName(alloc, p) orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    const def = try parseEntityDef(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
    switch (def) {
        .value => |sidx| {
            try p.gentity_map.put(alloc, name, sidx);
        },
        .external => |ext| {
            _ = ext;
            //TODO
        },
    }
    return .{
        .name = name,
        .def = def,
    };
}

/// PEDecl   ::=   '<!ENTITY' S '%' S Name S PEDef S? '>'
fn parsePEDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?PEDecl {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("%") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    const name = try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse return error.XmlMalformed;
    const def = try parsePEDef(alloc, p) orelse return error.XmlMalformed;
    try parseS(p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
    switch (def) {
        .entity_value => |sidx| {
            try p.pentity_map.put(alloc, name, sidx);
        },
        .external_id => |exid| {
            _ = exid;
            //TODO
        },
    }
    return .{
        .name = name,
        .def = def,
    };
}

/// Mixed   ::=   '(' S? '#PCDATA' (S? '|' S? Name)* S? ')*'
/// Mixed   ::=   '(' S? '#PCDATA' S? ')'
fn parseMixed(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringListIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try p.eat("#PCDATA") orelse return null;
    try parseS(p) orelse {};
    if (try p.eat(")")) |_| return .empty;

    var list = std.ArrayList(StringIndex).init(alloc);
    defer list.deinit();
    while (true) {
        try parseS(p) orelse {};
        try p.eat("|") orelse break;
        try parseS(p) orelse {};
        try list.append(try parseName(alloc, p) orelse return error.XmlMalformed);
    }
    try p.eat(")*") orelse return error.XmlMalformed;
    return try p.addStrList(alloc, list.items);
}

/// children   ::=   (choice | seq) ('?' | '*' | '+')?
/// choice     ::=   '(' S? cp ( S? '|' S? cp )+ S? ')'
/// seq        ::=   '(' S? cp ( S? ',' S? cp )* S? ')'
/// cp         ::=   (Name | choice | seq) ('?' | '*' | '+')?
fn parseChildren(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseChoiceOrSeq(alloc, p, true, null) orelse return null;
    _ = try p.eatEnumU8(ChildrenAmt) orelse {};
}

/// AttType   ::=   StringType | TokenizedType | EnumeratedType
fn parseAttType(alloc: std.mem.Allocator, p: *Parser) anyerror!?AttType {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parseStringType(p)) |_| return .{ .string = {} };
    if (try parseTokenizedType(p)) |v| return .{ .tokenized = v };
    if (try parseEnumeratedType(alloc, p)) |v| return .{ .enumerated = v };
    return null;
}

/// DefaultDecl   ::=   '#REQUIRED' | '#IMPLIED'
/// DefaultDecl   ::=   (('#FIXED' S)? AttValue)
fn parseDefaultDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try p.eat("#REQUIRED")) |_| return;
    if (try p.eat("#IMPLIED")) |_| return;

    if (try p.eat("#FIXED")) |_| {
        try parseS(p) orelse return error.XmlMalformed;
    }
    _ = try parseAttValue(alloc, p) orelse return error.XmlMalformed;
}

/// EntityDef   ::=   EntityValue | (ExternalID NDataDecl?)
fn parseEntityDef(alloc: std.mem.Allocator, p: *Parser) anyerror!?EntityDef {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parseEntityValue(alloc, p)) |ev| return .{ .value = ev };

    const id = try parseExternalOrPublicID(alloc, p, false) orelse return null;
    const ndata = try parseNDataDecl(alloc, p);
    return .{ .external = .{
        .id = id.external,
        .ndata = ndata,
    } };
}

/// PEDef   ::=   EntityValue | ExternalID
fn parsePEDef(alloc: std.mem.Allocator, p: *Parser) anyerror!?PEDef {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parseExternalOrPublicID(alloc, p, false)) |id| return .{ .external_id = id.external };
    if (try parseEntityValue(alloc, p)) |ev| return .{ .entity_value = ev };
    return null;
}

/// choice   ::=   '(' S? cp ( S? '|' S? cp )+ S? ')'
/// seq      ::=   '(' S? cp ( S? ',' S? cp )* S? ')'
/// cp       ::=   (Name | choice | seq) ('?' | '*' | '+')?
fn parseChoiceOrSeq(alloc: std.mem.Allocator, p: *Parser, started: bool, sep_start: ?u8) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (!started) {
        try p.eat("(") orelse return null;
        try parseS(p) orelse {};
        try parseCp(alloc, p, sep_start) orelse return error.XmlMalformed;
    } else {
        try parseCp(alloc, p, sep_start) orelse return null;
    }

    try parseS(p) orelse {};
    if (try p.eat(")")) |_| return;

    const sep = sep_start orelse try p.eatAny(&.{ '|', ',' }) orelse return error.XmlMalformed;
    if (sep_start != null) _ = try p.eatByte(sep);
    while (true) {
        try parseS(p) orelse {};
        try parseCp(alloc, p, sep) orelse break;
        try parseS(p) orelse {};
        _ = try p.eatByte(sep) orelse break;
    }
    try parseS(p) orelse {};
    try p.eat(")") orelse return error.XmlMalformed;
}

/// StringType   ::=   'CDATA'
fn parseStringType(p: *Parser) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    return p.eat("CDATA");
}

/// TokenizedType   ::=   'ID' | 'IDREF' | 'IDREFS' | 'ENTITY' | 'ENTITIES' | 'NMTOKEN' | 'NMTOKENS'
fn parseTokenizedType(p: *Parser) anyerror!?TokenizedType {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    return p.eatEnum(TokenizedType);
}

/// EnumeratedType   ::=   NotationType | Enumeration
fn parseEnumeratedType(alloc: std.mem.Allocator, p: *Parser) anyerror!?EnumeratedType {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    if (try parseNotationType(alloc, p)) |idx| return .{ .notation_type = idx };
    if (try parseEnumeration(alloc, p)) |idx| return .{ .enumeration = idx };
    return null;
}

/// EntityValue   ::=   '"' ([^%&"] | PEReference | Reference)* '"'
/// EntityValue   ::=   "'" ([^%&'] | PEReference | Reference)* "'"
fn parseEntityValue(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    const q = try p.eatQuoteS() orelse return null;
    while (true) blk: {
        if (try p.eatQuoteE(q)) |_| break;
        if (try p.eatAnyNot(&.{ '%', '&', q })) |b| break :blk try list.append(b);
        if (try parsePEReference(alloc, p)) |ref| break :blk try list.appendSlice(p.getStr(p.pentity_map.get(ref) orelse return error.XmlMalformed));
        if (try parseReference(alloc, p)) |ref| break :blk try addReferenceToList(p, &list, ref);
        unreachable;
    }
    return try p.addStr(alloc, list.items);
}

/// NDataDecl   ::=   S 'NDATA' S Name
fn parseNDataDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    try parseS(p) orelse return null;
    try p.eat("NDATA") orelse return error.XmlMalformed;
    try parseS(p) orelse return error.XmlMalformed;
    return try parseName(alloc, p) orelse return error.XmlMalformed;
}

/// cp   ::=   (Name | choice | seq) ('?' | '*' | '+')?
fn parseCp(alloc: std.mem.Allocator, p: *Parser, sep_start: ?u8) anyerror!?void {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    _ = try parseName(alloc, p) orelse {
        _ = try parseChoiceOrSeq(alloc, p, false, sep_start) orelse {
            return null;
        };
    };
    _ = try p.eatEnumU8(ChildrenAmt) orelse {};
}

/// NotationType   ::=   'NOTATION' S '(' S? Name (S? '|' S? Name)* S? ')'
fn parseNotationType(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringListIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(StringIndex).init(alloc);
    defer list.deinit();

    try p.eat("NOTATION") orelse return null;
    try parseS(p) orelse return error.XmlMalformed;
    try p.eat("(") orelse return error.XmlMalformed;
    try parseS(p) orelse {};
    try list.append(try parseName(alloc, p) orelse return error.XmlMalformed);
    while (true) {
        try parseS(p) orelse {};
        try p.eat("|") orelse break;
        try parseS(p) orelse {};
        try list.append(try parseName(alloc, p) orelse return error.XmlMalformed);
    }
    try parseS(p) orelse {};
    try p.eat(")") orelse return error.XmlMalformed;
    return try p.addStrList(alloc, list.items);
}

/// Enumeration   ::=   '(' S? Nmtoken (S? '|' S? Nmtoken)* S? ')'
fn parseEnumeration(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringListIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(StringIndex).init(alloc);
    defer list.deinit();

    try p.eat("(") orelse return null;
    try parseS(p) orelse {};
    try list.append(try parseNmtoken(alloc, p) orelse return error.XmlMalformed);
    while (true) {
        try parseS(p) orelse {};
        _ = try p.eatByte('|') orelse break;
        try parseS(p) orelse {};
        try list.append(try parseNmtoken(alloc, p) orelse return error.XmlMalformed);
    }
    try parseS(p) orelse {};
    try p.eat(")") orelse return error.XmlMalformed;
    return try p.addStrList(alloc, list.items);
}

/// Nmtoken   ::=   (NameChar)+
fn parseNmtoken(alloc: std.mem.Allocator, p: *Parser) anyerror!?StringIndex {
    const t = tracer.trace(@src(), "", .{});
    defer t.end();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    var i: usize = 0;
    while (true) : (i += 1) {
        if (try parseNameChar(p)) |c| {
            try addUCPtoList(&list, c);
            continue;
        }
        if (i == 0) return null;
        break;
    }
    return try p.addStr(alloc, list.items);
}

//
//

// Names   ::=   Name (#x20 Name)*
// Nmtokens   ::=   Nmtoken (#x20 Nmtoken)*
// extSubset   ::=   TextDecl? extSubsetDecl
// extSubsetDecl   ::=   ( markupdecl | conditionalSect | DeclSep)*
// SDDecl   ::=   S 'standalone' Eq (("'" ('yes' | 'no') "'") | ('"' ('yes' | 'no') '"'))
// conditionalSect   ::=   includeSect | ignoreSect
// includeSect   ::=   '<![' S? 'INCLUDE' S? '[' extSubsetDecl ']]>'
// ignoreSect   ::=   '<![' S? 'IGNORE' S? '[' ignoreSectContents* ']]>'
// ignoreSectContents   ::=   Ignore ('<![' ignoreSectContents ']]>' Ignore)*
// Ignore   ::=   Char* - (Char* ('<![' | ']]>') Char*)
// TextDecl   ::=   '<?xml' VersionInfo? EncodingDecl S? '?>'
// extParsedEnt   ::=   TextDecl? content

//
//

fn addUCPtoList(list: *std.ArrayList(u8), cp: u21) !void {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8CodepointSequenceLength(cp) catch unreachable;
    _ = std.unicode.utf8Encode(cp, buf[0..len]) catch unreachable;
    try list.appendSlice(buf[0..len]);
}

fn addReferenceToList(p: *Parser, list: *std.ArrayList(u8), ref: Reference) !void {
    return switch (ref) {
        .char => |c| addUCPtoList(list, c),
        .entity_found => |sidx| list.appendSlice(p.getStr(sidx)),
        .entity_name => |nm| list.appendSlice(p.getStr(p.gentity_map.get(nm) orelse blk: {
            log.warn("encountered unknown entity: &{s};", .{p.getStr(nm)});
            break :blk try p.addStr(list.allocator, "");
        })),
    };
}

fn addOpStringToList(p: *Parser, list: *std.ArrayList(u8), sidx_maybe: ?StringIndex) !void {
    // try list.appendSlice(p.getStr(sidx_maybe orelse try p.addStr(list.allocator, "")));
    try list.appendSlice(std.mem.trim(u8, p.getStr(sidx_maybe orelse try p.addStr(list.allocator, "")), " \n"));
}

//
//

pub const Document = struct {
    allocator: std.mem.Allocator,
    data: []const u32,
    string_bytes: []const u8,
    nodes: std.MultiArrayList(Parser.Node).Slice,
    root: Element,

    pub fn deinit(this: *Document) void {
        this.allocator.free(this.data);
        this.allocator.free(this.string_bytes);
        this.nodes.deinit(this.allocator);
    }

    pub fn str(this: *const Document, idx: StringIndex) string {
        const obj = this.data[@intFromEnum(idx)..][0..2].*;
        return this.string_bytes[obj[0]..][0..obj[1]];
    }

    pub fn elem_children(this: *const Document, elem: Element) []const NodeIndex {
        const eidx = elem.content orelse return &.{};
        if (eidx == .empty) return &.{};
        const handle = this.data[@intFromEnum(eidx)..];
        const len = handle[0];
        return @ptrCast(handle[1..][0..len]);
    }

    pub fn elem_attr(this: *const Document, elem: Element, key: string) ?string {
        const eidx = elem.attributes;
        if (eidx == .empty) return null;
        const handle = this.data[@intFromEnum(eidx)..];
        const len = handle[0] / 2;
        // error: TODO: implement @ptrCast between slices changing the length
        // const attributes: []const Attribute = @ptrCast(handle[1..][0..len]);
        // for (attributes) |item| {
        for (0..len) |i| {
            const item: Attribute = @bitCast(handle[1..][2 * i ..][0..2].*);
            if (std.mem.eql(u8, this.str(item.name), key)) {
                return this.str(item.value);
            }
        }
        return null;
    }

    pub fn node(this: *const Document, idx: NodeIndex) Parser.Node {
        return this.nodes.get(@intFromEnum(idx));
    }
};

pub const StringIndex = enum(u32) {
    _,
};

pub const StringListIndex = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub const AttributeListIndex = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub const NodeIndex = enum(u32) {
    _,
};

pub const NodeListIndex = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub const Standalone = enum {
    no,
    yes,
};

pub const Element = struct {
    tag_name: StringIndex,
    attributes: AttributeListIndex,
    content: ?NodeListIndex,

    pub fn children(el: Element, doc: *const Document) []const NodeIndex {
        return doc.elem_children(el);
    }

    pub fn attr(el: Element, doc: *const Document, key: string) ?string {
        return doc.elem_attr(el, key);
    }
};

pub const Reference = union(enum) {
    char: u21,
    entity_found: StringIndex,
    entity_name: StringIndex,
};

pub const ProcessingInstruction = struct {
    target: StringIndex,
    rest: StringIndex,
};

pub const TokenizedType = enum {
    IDREFS,
    IDREF,
    ID,
    ENTITY,
    ENTITIES,
    NMTOKENS,
    NMTOKEN,
};

pub const EnumeratedType = union(enum) {
    notation_type: StringListIndex,
    enumeration: StringListIndex,
};

pub const AttType = union(enum) {
    string: void,
    tokenized: TokenizedType,
    enumerated: EnumeratedType,
};

pub const XMLDecl = struct {
    encoding: ?StringIndex,
    standalone: Standalone,
};

pub const ID = union(enum) {
    public: StringIndex,
    external: ExternalID,
};

pub const ExternalID = union(enum) {
    system: StringIndex,
    public: [2]StringIndex,
};

pub const Misc = union(enum) {
    comment: void,
    pi: ProcessingInstruction,
    s: void,
};

pub const NotationDecl = struct {
    name: StringIndex,
    id: ID,
};

pub const DeclSep = union(enum) {
    pe_ref: StringIndex,
    s: void,
};

pub const ChildrenAmt = enum(u8) {
    op = '?',
    star = '*',
    plus = '+',
};

pub const PEDef = union(enum) {
    entity_value: StringIndex,
    external_id: ExternalID,
};

pub const EntityDef = union(enum) {
    value: StringIndex,
    external: struct {
        id: ExternalID,
        ndata: ?StringIndex,
    },
};

pub const PEDecl = struct {
    name: StringIndex,
    def: PEDef,
};

pub const GEDecl = struct {
    name: StringIndex,
    def: EntityDef,
};

pub const EntityDecl = union(enum) {
    ge: GEDecl,
    pe: PEDecl,
};

pub const Attribute = extern struct {
    name: StringIndex,
    value: StringIndex,
};
