//! Parser for Extensible Markup Language (XML)
//! https://www.w3.org/TR/xml/
// https://www.w3.org/XML/Test/xmlconf-20020606.htm

const std = @import("std");
const string = []const u8;
const extras = @import("extras");
const OurReader = @import("./OurReader.zig");

//
//

pub fn parse(alloc: std.mem.Allocator, path: string, inreader: std.fs.File.Reader) !void {
    var bufread = std.io.bufferedReader(inreader);
    var counter = std.io.countingReader(bufread.reader());
    const anyreader = extras.AnyReader.from(counter.reader());
    var ourreader = OurReader{ .any = anyreader };
    return parseDocument(alloc, &ourreader) catch |err| switch (err) {
        error.XmlMalformed => {
            std.log.err("{s}:{d}:{d}: {d}'{s}'", .{ path, ourreader.line, ourreader.col, ourreader.amt, ourreader.buf });
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
            return err;
        },
        else => |e| e,
    };
}

/// document   ::=   prolog element Misc*
fn parseDocument(alloc: std.mem.Allocator, reader: *OurReader) anyerror!void {
    _ = try parseProlog(alloc, reader);
    _ = try parseElement(alloc, reader);
    while (true) try parseMisc(alloc, reader) orelse break;
}

/// prolog   ::=   XMLDecl? Misc* (doctypedecl Misc*)?
fn parseProlog(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseXMLDecl(alloc, reader) orelse {};
    while (true) try parseMisc(alloc, reader) orelse break;
    try parseDoctypeDecl(alloc, reader) orelse return;
    while (true) try parseMisc(alloc, reader) orelse break;
}

/// element   ::=   EmptyElemTag
/// element   ::=   STag content ETag
fn parseElement(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseSTag(alloc, reader) orelse {
        try parseEmptyElemTag(alloc, reader) orelse return null;
        return;
    };
    try parseContent(alloc, reader) orelse return error.XmlMalformed;
    try parseETag(alloc, reader) orelse return error.XmlMalformed;
}

/// Misc   ::=   Comment | PI | S
fn parseMisc(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseComment(alloc, reader) orelse {
        try parsePI(alloc, reader) orelse {
            try parseS(alloc, reader) orelse {
                return null;
            };
        };
    };
}

/// XMLDecl   ::=   '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'
fn parseXMLDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<?xml") orelse return null;
    try parseVersionInfo(alloc, reader) orelse return error.XmlMalformed;
    _ = try parseEncodingDecl(alloc, reader) orelse {};
    _ = try parseSDDecl(alloc, reader) orelse {};
    _ = try parseS(alloc, reader) orelse {};
    try reader.eat("?>") orelse return error.XmlMalformed;
}

/// doctypedecl   ::=   '<!DOCTYPE' S Name (S ExternalID)? S? ('[' intSubset ']' S?)? '>'
fn parseDoctypeDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<!DOCTYPE") orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try parseExternalID(alloc, reader) orelse {};
    try parseS(alloc, reader) orelse {};
    if (try reader.eat("[")) |_| {
        try parseIntSubset(alloc, reader) orelse return error.XmlMalformed;
        try reader.eat("]") orelse return error.XmlMalformed;
        try parseS(alloc, reader) orelse {};
    }
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// EmptyElemTag   ::=   '<' Name (S Attribute)* S? '/>'
fn parseEmptyElemTag(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    if (try reader.peek("</")) return null;
    if (try reader.peek("<!")) return null;
    try reader.eat("<") orelse return null;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    while (true) {
        try parseS(alloc, reader) orelse break;
        try parseAttribute(alloc, reader) orelse return error.XmlMalformed;
    }
    try parseS(alloc, reader) orelse {};
    try reader.eat("/>") orelse return error.XmlMalformed;
}

/// STag   ::=   '<' Name (S Attribute)* S? '>'
fn parseSTag(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    if (try reader.peek("</")) return null;
    if (try reader.peek("<!")) return null;
    try reader.eat("<") orelse return null;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    while (true) {
        try parseS(alloc, reader) orelse break;
        try parseAttribute(alloc, reader) orelse return error.XmlMalformed;
    }
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// content   ::=   CharData? ((element | Reference | CDSect | PI | Comment) CharData?)*
fn parseContent(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseCharData(alloc, reader) orelse {};
    while (true) {
        try parseElement(alloc, reader) orelse {
            try parseReference(alloc, reader) orelse {
                try parseCDSect(alloc, reader) orelse {
                    try parsePI(alloc, reader) orelse {
                        try parseComment(alloc, reader) orelse break;
                    };
                };
            };
        };
        try parseCharData(alloc, reader) orelse {};
    }
}

/// ETag   ::=   '</' Name S? '>'
fn parseETag(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("</") orelse return null;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// Comment   ::=   '<!--' ((Char - '-') | ('-' (Char - '-')))* '-->'
fn parseComment(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    _ = &parseChar;
    try reader.eat("<!--") orelse return null;
    try reader.skipUntilAfter("-->");
}

/// PI   ::=   '<?' PITarget (S (Char* - (Char* '?>' Char*)))? '?>'
fn parsePI(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<?") orelse return null;
    try parsePITarget(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try reader.skipUntilAfter("?>");
}

/// S   ::=   (#x20 | #x9 | #xD | #xA)+
fn parseS(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try reader.eatAny(&.{ 0x20, 0x09, 0x0D, 0x0A })) |_| continue; // space, \t, \r, \n
        if (i == 0) return null;
        break;
    }
}

/// VersionInfo   ::=   S 'version' Eq ("'" VersionNum "'" | '"' VersionNum '"')
fn parseVersionInfo(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseS(alloc, reader) orelse return null;
    try reader.eat("version") orelse return error.XmlMalformed;
    try parseEq(alloc, reader) orelse return error.XmlMalformed;
    const q = try reader.eatQuoteS() orelse return error.XmlMalformed;
    try parseVersionNum(alloc, reader) orelse return error.XmlMalformed;
    try reader.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// EncodingDecl   ::=   S 'encoding' Eq ('"' EncName '"' | "'" EncName "'" )
fn parseEncodingDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseS(alloc, reader) orelse {};
    try reader.eat("encoding") orelse return null;
    try parseEq(alloc, reader) orelse return error.XmlMalformed;
    const q = try reader.eatQuoteS() orelse return error.XmlMalformed;
    try parseEncName(alloc, reader) orelse return error.XmlMalformed;
    try reader.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// SDDecl   ::=   S 'standalone' Eq (("'" ('yes' | 'no') "'") | ('"' ('yes' | 'no') '"'))
fn parseSDDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseS(alloc, reader) orelse {};
    try reader.eat("standalone") orelse return null;
    try parseEq(alloc, reader) orelse return error.XmlMalformed;
    const q = try reader.eatQuoteS() orelse return error.XmlMalformed;
    try reader.eat("yes") orelse try reader.eat("no") orelse return error.XmlMalformed;
    try reader.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// Name   ::=   NameStartChar (NameChar)*
fn parseName(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = try parseNameStartChar(alloc, reader) orelse return null;
    while (true) {
        _ = try parseNameChar(alloc, reader) orelse break;
    }
}

/// ExternalID   ::=   'SYSTEM' S SystemLiteral
/// ExternalID   ::=   'PUBLIC' S PubidLiteral S SystemLiteral
fn parseExternalID(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("SYSTEM") orelse {
        try reader.eat("PUBLIC") orelse return null;
        try parseS(alloc, reader) orelse return error.XmlMalformed;
        try parsePubidLiteral(alloc, reader) orelse return error.XmlMalformed;
        try parseS(alloc, reader) orelse return error.XmlMalformed;
        try parseSystemLiteral(alloc, reader) orelse return error.XmlMalformed;
        return;
    };
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseSystemLiteral(alloc, reader) orelse return error.XmlMalformed;
}

/// intSubset   ::=   (markupdecl | DeclSep)*
fn parseIntSubset(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseMarkupDecl(alloc, reader) orelse try parseDeclSep(alloc, reader) orelse return null;
    while (true) {
        try parseMarkupDecl(alloc, reader) orelse try parseDeclSep(alloc, reader) orelse break;
    }
}

/// Attribute   ::=   Name Eq AttValue
fn parseAttribute(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseName(alloc, reader) orelse return null;
    try parseEq(alloc, reader) orelse return error.XmlMalformed;
    try parseAttValue(alloc, reader) orelse return error.XmlMalformed;
}

/// CharData   ::=   [^<&]* - ([^<&]* ']]>' [^<&]*)
fn parseCharData(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try reader.peek("]]>")) break;
        if (try reader.eatAnyNot("<&")) |_| continue;
        if (i == 0) return null;
        break;
    }
}

/// Reference   ::=   EntityRef | CharRef
fn parseReference(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseCharRef(alloc, reader) orelse try parseEntityRef(alloc, reader) orelse return null;
}

/// CDSect   ::=   CDStart CData CDEnd
fn parseCDSect(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseCDStart(alloc, reader) orelse return null;
    try parseCData(alloc, reader) orelse return error.XmlMalformed;
    try parseCDEnd(alloc, reader) orelse return error.XmlMalformed;
}

/// PITarget   ::=   Name - (('X' | 'x') ('M' | 'm') ('L' | 'l'))
fn parsePITarget(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    if (try reader.peek("xml ")) return null;
    if (try reader.peek("XML ")) return null;
    try parseName(alloc, reader) orelse return null;
}

/// Char   ::=   #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]	/* any Unicode character, excluding the surrogate blocks, FFFE, and FFFF. */
fn parseChar(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?u21 {
    _ = alloc;
    try reader.peekAmt(3) orelse return null;
    if (std.unicode.utf8Decode(reader.buf[0..1]) catch null) |cp| {
        reader.shiftLAmt(1);
        return cp;
    }
    if (std.unicode.utf8Decode(reader.buf[0..2]) catch null) |cp| {
        reader.shiftLAmt(2);
        return cp;
    }
    if (std.unicode.utf8Decode(reader.buf[0..3]) catch null) |cp| {
        reader.shiftLAmt(3);
        return cp;
    }
    return null;
}

/// Eq   ::=   S? '=' S?
fn parseEq(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseS(alloc, reader) orelse {};
    try reader.eat("=") orelse return null;
    try parseS(alloc, reader) orelse {};
}

/// VersionNum   ::=   '1.' [0-9]+
fn parseVersionNum(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    try reader.eat("1.") orelse return null;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try reader.eatRange('0', '9')) |_| continue;
        if (i == 0) return null;
        break;
    }
}

/// EncName   ::=   [A-Za-z] ([A-Za-z0-9._] | '-')*
fn parseEncName(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    _ = try reader.eatRange('A', 'Z') orelse try reader.eatRange('a', 'z') orelse return null;
    while (true) {
        if (try reader.eatRange('A', 'Z')) |_| continue;
        if (try reader.eatRange('a', 'z')) |_| continue;
        if (try reader.eatRange('0', '9')) |_| continue;
        if (try reader.eat(".")) |_| continue;
        if (try reader.eat("_")) |_| continue;
        if (try reader.eat("-")) |_| continue;
        break;
    }
}

/// NameStartChar   ::=   ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
fn parseNameStartChar(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?u21 {
    _ = alloc;
    if (try reader.eatByte(':')) |b| return b;
    if (try reader.eatRange('A', 'Z')) |b| return b;
    if (try reader.eatByte('_')) |b| return b;
    if (try reader.eatRange('a', 'z')) |b| return b;
    if (try reader.eatRange(0xC0, 0xD6)) |b| return b;
    if (try reader.eatRange(0xD8, 0xF6)) |b| return b;
    // [#xF8-#x2FF]
    // [#x370-#x37D]
    // [#x37F-#x1FFF]
    // [#x200C-#x200D]
    // [#x2070-#x218F]
    // [#x2C00-#x2FEF]
    // [#x3001-#xD7FF]
    // [#xF900-#xFDCF]
    // [#xFDF0-#xFFFD]
    // [#x10000-#xEFFFF]
    return null;
}

/// NameChar   ::=   NameStartChar | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
fn parseNameChar(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?u21 {
    if (try parseNameStartChar(alloc, reader)) |b| return b;
    if (try reader.eatByte('-')) |b| return b;
    if (try reader.eatByte('.')) |b| return b;
    if (try reader.eatRange('0', '9')) |b| return b;
    if (try reader.eatByte(0xB7)) |b| return b;
    // [#x0300-#x036F]
    // [#x203F-#x2040]
    return null;
}

/// SystemLiteral   ::=   ('"' [^"]* '"')
/// SystemLiteral   ::=   ("'" [^']* "'")
fn parseSystemLiteral(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    try reader.eat(&.{'"'}) orelse return null;
    try reader.skipUntilAfter(&.{'"'});
}

/// PubidLiteral   ::=   '"' PubidChar* '"' | "'" (PubidChar - "'")* "'"
fn parsePubidLiteral(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat(&.{'"'}) orelse return null;
    while (true) _ = try parsePubidChar(alloc, reader) orelse break;
    try reader.eat(&.{'"'}) orelse return error.XmlMalformed;
}

/// markupdecl   ::=   elementdecl | AttlistDecl | EntityDecl | NotationDecl | PI | Comment
fn parseMarkupDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    return try parseElementDecl(alloc, reader) orelse
        try parseAttlistDecl(alloc, reader) orelse
        try parseEntityDecl(alloc, reader) orelse
        try parseNotationDecl(alloc, reader) orelse
        try parsePI(alloc, reader) orelse
        try parseComment(alloc, reader) orelse
        null;
}

/// DeclSep   ::=   PEReference | S
fn parseDeclSep(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    return try parsePEReference(alloc, reader) orelse
        try parseS(alloc, reader) orelse
        null;
}

/// AttValue   ::=   '"' ([^<&"] | Reference)* '"'
/// AttValue   ::=   "'" ([^<&'] | Reference)* "'"
fn parseAttValue(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    const q = try reader.eatQuoteS() orelse return null;
    while (true) {
        if (try reader.eatQuoteE(q)) |_| break;
        if (try reader.eatAnyNot(&.{ '<', '&', q })) |_| continue;
        if (try parseReference(alloc, reader)) |_| continue;
        unreachable;
    }
}

/// EntityRef   ::=   '&' Name ';'
fn parseEntityRef(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("&") orelse return null;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try reader.eat(";") orelse return error.XmlMalformed;
}

/// CharRef   ::=   '&#' [0-9]+ ';'
/// CharRef   ::=   '&#x' [0-9a-fA-F]+ ';'
fn parseCharRef(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    try reader.eat("&#x") orelse {
        try reader.eat("&#") orelse return null;
        var i: usize = 0;
        while (true) : (i += 1) {
            if (try reader.eatRange('0', '9')) |_| continue;
            if (i == 0) return error.XmlMalformed;
            break;
        }
        try reader.eat(";") orelse return error.XmlMalformed;
        return;
    };
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try reader.eatRange('0', '9')) |_| continue;
        if (try reader.eatRange('a', 'f')) |_| continue;
        if (try reader.eatRange('A', 'F')) |_| continue;
        if (i == 0) return error.XmlMalformed;
        break;
    }
    try reader.eat(";") orelse return error.XmlMalformed;
}

/// CDStart   ::=   '<![CDATA['
fn parseCDStart(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    try reader.eat("<![CDATA[") orelse return null;
}

/// CData   ::=   (Char* - (Char* ']]>' Char*))
fn parseCData(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    while (true) {
        if (try reader.peek("]]>")) break;
        _ = try parseChar(alloc, reader) orelse return error.XmlMalformed;
    }
}

/// CDEnd   ::=   ']]>'
fn parseCDEnd(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    return reader.eat("]]>");
}

/// PubidChar   ::=   #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
fn parsePubidChar(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?u21 {
    _ = alloc;
    if (try reader.eatByte(0x20)) |b| return b;
    if (try reader.eatByte(0x0D)) |b| return b;
    if (try reader.eatByte(0x0A)) |b| return b;
    if (try reader.eatRange('a', 'z')) |b| return b;
    if (try reader.eatRange('A', 'Z')) |b| return b;
    if (try reader.eatRange('0', '9')) |b| return b;
    if (try reader.eatAny("-'()+,./:=?;!*#@$_%")) |b| return b;
    return null;
}

/// elementdecl   ::=   '<!ELEMENT' S Name S contentspec S? '>'
fn parseElementDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<!ELEMENT") orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseContentSpec(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// AttlistDecl   ::=   '<!ATTLIST' S Name AttDef* S? '>'
fn parseAttlistDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<!ATTLIST") orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    while (true) try parseAttDef(alloc, reader) orelse break;
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// EntityDecl   ::=   GEDecl | PEDecl
fn parseEntityDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<!ENTITY") orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    return try parseGEDecl(alloc, reader) orelse
        try parsePEDecl(alloc, reader) orelse
        return null;
}

/// NotationDecl   ::=   '<!NOTATION' S Name S (ExternalID | PublicID) S? '>'
fn parseNotationDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("<!NOTATION") orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseExternalID(alloc, reader) orelse try parsePublicID(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// PEReference   ::=   '%' Name ';'
fn parsePEReference(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("%") orelse return null;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try reader.eat(";") orelse return error.XmlMalformed;
}

/// contentspec   ::=   'EMPTY' | 'ANY' | Mixed | children
fn parseContentSpec(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    if (try reader.eat("EMPTY")) |_| return;
    if (try reader.eat("ANY")) |_| return;

    try reader.eat("(") orelse return null;
    try parseS(alloc, reader) orelse {};
    if (try parseMixed(alloc, reader)) |_| return;
    if (try parseChildren(alloc, reader)) |_| return;
    return null;
}

/// AttDef   ::=   S Name S AttType S DefaultDecl
fn parseAttDef(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseS(alloc, reader) orelse return null;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseAttType(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseDefaultDecl(alloc, reader) orelse return error.XmlMalformed;
}

/// GEDecl   ::=   '<!ENTITY' S Name S EntityDef S? '>'
fn parseGEDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseName(alloc, reader) orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseEntityDef(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// PEDecl   ::=   '<!ENTITY' S '%' S Name S PEDef S? '>'
fn parsePEDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("%") orelse return null;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parsePEDef(alloc, reader) orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse {};
    try reader.eat(">") orelse return error.XmlMalformed;
}

/// PublicID   ::=   'PUBLIC' S PubidLiteral
fn parsePublicID(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    //
    _ = alloc;
    _ = reader;
    _ = &parseS;
    _ = &parsePubidLiteral;
    return error.TODO; // TODO:
}

/// Mixed   ::=   '(' S? '#PCDATA' (S? '|' S? Name)* S? ')*'
/// Mixed   ::=   '(' S? '#PCDATA' S? ')'
fn parseMixed(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try reader.eat("#PCDATA") orelse return null;
    try parseS(alloc, reader) orelse {};
    if (try reader.eat(")")) |_| return;
    while (true) {
        try parseS(alloc, reader) orelse {};
        try reader.eat("|") orelse break;
        try parseS(alloc, reader) orelse {};
        try parseName(alloc, reader) orelse return error.XmlMalformed;
    }
    try reader.eat(")*") orelse return error.XmlMalformed;
}

/// children   ::=   (choice | seq) ('?' | '*' | '+')?
fn parseChildren(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseChoice(alloc, reader) orelse try parseSeq(alloc, reader) orelse return null;
    _ = try reader.eatAny(&.{ '?', '*', '+' }) orelse {};
}

/// AttType   ::=   StringType | TokenizedType | EnumeratedType
fn parseAttType(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    return try parseStringType(alloc, reader) orelse
        try parseTokenizedType(alloc, reader) orelse
        try parseEnumeratedType(alloc, reader) orelse
        null;
}

/// DefaultDecl   ::=   '#REQUIRED' | '#IMPLIED'
/// DefaultDecl   ::=   (('#FIXED' S)? AttValue)
fn parseDefaultDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    if (try reader.eat("#REQUIRED")) |_| return;
    if (try reader.eat("#IMPLIED")) |_| return;

    if (try reader.eat("#FIXED")) |_| {
        try parseS(alloc, reader) orelse return error.XmlMalformed;
    }
    try parseAttValue(alloc, reader) orelse return error.XmlMalformed;
}

/// EntityDef   ::=   EntityValue | (ExternalID NDataDecl?)
fn parseEntityDef(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    return try parseEntityValue(alloc, reader) orelse {
        try parseExternalID(alloc, reader) orelse return null;
        try parseNDataDecl(alloc, reader) orelse {};
        return;
    };
}

/// PEDef   ::=   EntityValue | ExternalID
fn parsePEDef(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    return try parseExternalID(alloc, reader) orelse
        try parseEntityValue(alloc, reader) orelse
        null;
}

/// choice   ::=   '(' S? cp ( S? '|' S? cp )+ S? ')'
fn parseChoice(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseCp(alloc, reader) orelse return null;
    var i: usize = 0;
    while (true) : (i += 1) {
        try parseS(alloc, reader) orelse {};
        try reader.eat("|") orelse if (i == 0) return error.XmlMalformed else break;
        try parseS(alloc, reader) orelse {};
        try parseCp(alloc, reader) orelse return error.XmlMalformed;
    }
    try parseS(alloc, reader) orelse {};
    try reader.eat(")") orelse return error.XmlMalformed;
}

/// seq   ::=   '(' S? cp ( S? ',' S? cp )* S? ')'
fn parseSeq(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseCp(alloc, reader) orelse return null;
    var i: usize = 0;
    while (true) : (i += 1) {
        try parseS(alloc, reader) orelse {};
        try reader.eat(",") orelse if (i == 0) return error.XmlMalformed else break;
        try parseS(alloc, reader) orelse {};
        try parseCp(alloc, reader) orelse return error.XmlMalformed;
    }
    try parseS(alloc, reader) orelse {};
    try reader.eat(")") orelse return error.XmlMalformed;
}

/// StringType   ::=   'CDATA'
fn parseStringType(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    return reader.eat("CDATA");
}

/// TokenizedType   ::=   'ID' | 'IDREF' | 'IDREFS' | 'ENTITY' | 'ENTITIES' | 'NMTOKEN' | 'NMTOKENS'
fn parseTokenizedType(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    _ = alloc;
    if (try reader.eat("ID")) |_| return;
    if (try reader.eat("IDREFS")) |_| return;
    if (try reader.eat("IDREF")) |_| return;
    if (try reader.eat("ENTITY")) |_| return;
    if (try reader.eat("ENTITIES")) |_| return;
    if (try reader.eat("NMTOKENS")) |_| return;
    if (try reader.eat("NMTOKEN")) |_| return;
    return null;
}

/// EnumeratedType   ::=   NotationType | Enumeration
fn parseEnumeratedType(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    return try parseNotationType(alloc, reader) orelse
        try parseEnumeration(alloc, reader) orelse
        null;
}

/// EntityValue   ::=   '"' ([^%&"] | PEReference | Reference)* '"'
/// EntityValue   ::=   "'" ([^%&'] | PEReference | Reference)* "'"
fn parseEntityValue(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    const q = try reader.eatQuoteS() orelse return null;
    while (true) {
        if (try reader.eatQuoteE(q)) |_| break;
        if (try reader.eatAnyNot(&.{ '%', '&', q })) |_| continue;
        if (try parsePEReference(alloc, reader)) |_| continue;
        if (try parseReference(alloc, reader)) |_| continue;
        unreachable;
    }
}

/// NDataDecl   ::=   S 'NDATA' S Name
fn parseNDataDecl(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseS(alloc, reader) orelse return null;
    try reader.eat("NDATA") orelse return error.XmlMalformed;
    try parseS(alloc, reader) orelse return error.XmlMalformed;
    try parseName(alloc, reader) orelse return error.XmlMalformed;
}

/// cp   ::=   (Name | choice | seq) ('?' | '*' | '+')?
fn parseCp(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    try parseName(alloc, reader) orelse try parseChoice(alloc, reader) orelse try parseSeq(alloc, reader) orelse return null;
    _ = try reader.eatAny(&.{ '?', '*', '+' }) orelse {};
}

/// NotationType   ::=   'NOTATION' S '(' S? Name (S? '|' S? Name)* S? ')'
fn parseNotationType(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    //
    _ = alloc;
    _ = reader;
    _ = &parseS;
    _ = &parseName;
    return error.TODO; // TODO:
}

/// Enumeration   ::=   '(' S? Nmtoken (S? '|' S? Nmtoken)* S? ')'
fn parseEnumeration(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    //
    _ = alloc;
    _ = reader;
    _ = &parseS;
    _ = &parseNmtoken;
    return error.TODO; // TODO:
}

/// Nmtoken   ::=   (NameChar)+
fn parseNmtoken(alloc: std.mem.Allocator, reader: *OurReader) anyerror!?void {
    //
    _ = alloc;
    _ = reader;
    _ = &parseNameChar;
    return error.TODO; // TODO:
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
