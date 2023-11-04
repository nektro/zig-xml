//! Parser for Extensible Markup Language (XML)
//! https://www.w3.org/TR/xml/
// https://www.w3.org/XML/Test/xmlconf-20020606.htm

const std = @import("std");
const string = []const u8;
const extras = @import("extras");
const Parser = @import("./Parser.zig");

//
//

pub fn parse(alloc: std.mem.Allocator, path: string, inreader: std.fs.File.Reader) !void {
    var bufread = std.io.bufferedReader(inreader);
    var counter = std.io.countingReader(bufread.reader());
    const anyreader = extras.AnyReader.from(counter.reader());
    var ourreader = Parser{ .any = anyreader };
    return parseDocument(alloc, &ourreader) catch |err| switch (err) {
        error.XmlMalformed => {
            std.log.err("{s}:{d}:{d}: {d}'{s}'", .{ path, ourreader.line, ourreader.col -| ourreader.amt, ourreader.amt, ourreader.buf });
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
            return err;
        },
        else => |e| e,
    };
}

/// document   ::=   prolog element Misc*
fn parseDocument(alloc: std.mem.Allocator, p: *Parser) anyerror!void {
    _ = try parseProlog(alloc, p);
    _ = try parseElement(alloc, p);
    while (true) try parseMisc(alloc, p) orelse break;
}

/// prolog   ::=   XMLDecl? Misc* (doctypedecl Misc*)?
fn parseProlog(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseXMLDecl(alloc, p) orelse {};
    while (true) try parseMisc(alloc, p) orelse break;
    try parseDoctypeDecl(alloc, p) orelse return;
    while (true) try parseMisc(alloc, p) orelse break;
}

/// element   ::=   EmptyElemTag
/// element   ::=   STag content ETag
///
/// EmptyElemTag   ::=   '<' Name (S Attribute)* S? '/>'
/// STag           ::=   '<' Name (S Attribute)* S? '>'
fn parseElement(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    if (try p.peek("</")) return null;
    if (try p.peek("<!")) return null;
    try p.eat("<") orelse return null;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    while (true) {
        try parseS(alloc, p) orelse {};
        try parseAttribute(alloc, p) orelse break;
    }
    try parseS(alloc, p) orelse {};
    if (try p.eat("/>")) |_| return;
    try p.eat(">") orelse return error.XmlMalformed;

    try parseContent(alloc, p) orelse return error.XmlMalformed;
    try parseETag(alloc, p) orelse return error.XmlMalformed;
}

/// Misc   ::=   Comment | PI | S
fn parseMisc(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseComment(alloc, p) orelse {
        try parsePI(alloc, p) orelse {
            try parseS(alloc, p) orelse {
                return null;
            };
        };
    };
}

/// XMLDecl   ::=   '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'
fn parseXMLDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<?xml") orelse return null;
    try parseVersionInfo(alloc, p) orelse return error.XmlMalformed;
    _ = try parseEncodingDecl(alloc, p) orelse {};
    _ = try parseSDDecl(alloc, p) orelse {};
    _ = try parseS(alloc, p) orelse {};
    try p.eat("?>") orelse return error.XmlMalformed;
}

/// doctypedecl   ::=   '<!DOCTYPE' S Name (S ExternalID)? S? ('[' intSubset ']' S?)? '>'
fn parseDoctypeDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<!DOCTYPE") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try parseExternalOrPublicID(alloc, p, false) orelse {};
    try parseS(alloc, p) orelse {};
    if (try p.eat("[")) |_| {
        try parseIntSubset(alloc, p) orelse return error.XmlMalformed;
        try p.eat("]") orelse return error.XmlMalformed;
        try parseS(alloc, p) orelse {};
    }
    try p.eat(">") orelse return error.XmlMalformed;
}

/// content   ::=   CharData? ((element | Reference | CDSect | PI | Comment) CharData?)*
fn parseContent(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseCharData(alloc, p) orelse {};
    while (true) {
        try parsePI(alloc, p) orelse {
            try parseElement(alloc, p) orelse {
                try parseReference(alloc, p) orelse {
                    try parseCDSect(alloc, p) orelse {
                        try parseComment(alloc, p) orelse break;
                    };
                };
            };
        };
        try parseCharData(alloc, p) orelse {};
    }
}

/// ETag   ::=   '</' Name S? '>'
fn parseETag(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("</") orelse return null;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// Comment   ::=   '<!--' ((Char - '-') | ('-' (Char - '-')))* '-->'
fn parseComment(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<!--") orelse return null;
    while (true) {
        if (try p.eat("-->")) |_| break;
        _ = try parseChar(alloc, p) orelse return error.XmlMalformed;
    }
}

/// PI   ::=   '<?' PITarget (S (Char* - (Char* '?>' Char*)))? '?>'
fn parsePI(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<?") orelse return null;
    try parsePITarget(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try p.skipUntilAfter("?>");
}

/// S   ::=   (#x20 | #x9 | #xD | #xA)+
fn parseS(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.eatAny(&.{ 0x20, 0x09, 0x0D, 0x0A })) |_| continue; // space, \t, \r, \n
        if (i == 0) return null;
        break;
    }
}

/// VersionInfo   ::=   S 'version' Eq ("'" VersionNum "'" | '"' VersionNum '"')
fn parseVersionInfo(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseS(alloc, p) orelse return null;
    try p.eat("version") orelse return error.XmlMalformed;
    try parseEq(alloc, p) orelse return error.XmlMalformed;
    const q = try p.eatQuoteS() orelse return error.XmlMalformed;
    try parseVersionNum(alloc, p) orelse return error.XmlMalformed;
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// EncodingDecl   ::=   S 'encoding' Eq ('"' EncName '"' | "'" EncName "'" )
fn parseEncodingDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseS(alloc, p) orelse {};
    try p.eat("encoding") orelse return null;
    try parseEq(alloc, p) orelse return error.XmlMalformed;
    const q = try p.eatQuoteS() orelse return error.XmlMalformed;
    try parseEncName(alloc, p) orelse return error.XmlMalformed;
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// SDDecl   ::=   S 'standalone' Eq (("'" ('yes' | 'no') "'") | ('"' ('yes' | 'no') '"'))
fn parseSDDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseS(alloc, p) orelse {};
    try p.eat("standalone") orelse return null;
    try parseEq(alloc, p) orelse return error.XmlMalformed;
    const q = try p.eatQuoteS() orelse return error.XmlMalformed;
    try p.eat("yes") orelse try p.eat("no") orelse return error.XmlMalformed;
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// Name   ::=   NameStartChar (NameChar)*
fn parseName(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = try parseNameStartChar(alloc, p) orelse return null;
    while (true) {
        _ = try parseNameChar(alloc, p) orelse break;
    }
}

/// ExternalID   ::=   'SYSTEM' S SystemLiteral
/// PublicID     ::=   'PUBLIC' S PubidLiteral
/// ExternalID   ::=   'PUBLIC' S PubidLiteral S SystemLiteral
fn parseExternalOrPublicID(alloc: std.mem.Allocator, p: *Parser, allow_public: bool) anyerror!?void {
    try p.eat("SYSTEM") orelse {
        try p.eat("PUBLIC") orelse return null;
        try parseS(alloc, p) orelse return error.XmlMalformed;
        try parsePubidLiteral(alloc, p) orelse return error.XmlMalformed;
        try parseS(alloc, p) orelse return if (allow_public) {} else error.XmlMalformed;
        try parseSystemLiteral(alloc, p) orelse return error.XmlMalformed;
        return;
    };
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseSystemLiteral(alloc, p) orelse return error.XmlMalformed;
}

/// intSubset   ::=   (markupdecl | DeclSep)*
fn parseIntSubset(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseMarkupDecl(alloc, p) orelse try parseDeclSep(alloc, p) orelse return null;
    while (true) {
        try parseMarkupDecl(alloc, p) orelse try parseDeclSep(alloc, p) orelse break;
    }
}

/// Attribute   ::=   Name Eq AttValue
fn parseAttribute(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseName(alloc, p) orelse return null;
    try parseEq(alloc, p) orelse return error.XmlMalformed;
    try parseAttValue(alloc, p) orelse return error.XmlMalformed;
}

/// CharData   ::=   [^<&]* - ([^<&]* ']]>' [^<&]*)
fn parseCharData(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.peek("]]>")) break;
        if (try p.eatAnyNot("<&")) |_| continue;
        if (i == 0) return null;
        break;
    }
}

/// Reference   ::=   EntityRef | CharRef
fn parseReference(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseCharRef(alloc, p) orelse try parseEntityRef(alloc, p) orelse return null;
}

/// CDSect   ::=   CDStart CData CDEnd
fn parseCDSect(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseCDStart(alloc, p) orelse return null;
    try parseCData(alloc, p) orelse return error.XmlMalformed;
    try parseCDEnd(alloc, p) orelse return error.XmlMalformed;
}

/// PITarget   ::=   Name - (('X' | 'x') ('M' | 'm') ('L' | 'l'))
fn parsePITarget(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    if (try p.peek("xml ")) return null;
    if (try p.peek("XML ")) return null;
    try parseName(alloc, p) orelse return null;
}

/// Char   ::=   #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]	/* any Unicode character, excluding the surrogate blocks, FFFE, and FFFF. */
fn parseChar(alloc: std.mem.Allocator, p: *Parser) anyerror!?u21 {
    _ = alloc;
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
fn parseEq(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseS(alloc, p) orelse {};
    try p.eat("=") orelse return null;
    try parseS(alloc, p) orelse {};
}

/// VersionNum   ::=   '1.' [0-9]+
fn parseVersionNum(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    try p.eat("1.") orelse return null;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.eatRange('0', '9')) |_| continue;
        if (i == 0) return null;
        break;
    }
}

/// EncName   ::=   [A-Za-z] ([A-Za-z0-9._] | '-')*
fn parseEncName(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    _ = try p.eatRange('A', 'Z') orelse try p.eatRange('a', 'z') orelse return null;
    while (true) {
        if (try p.eatRange('A', 'Z')) |_| continue;
        if (try p.eatRange('a', 'z')) |_| continue;
        if (try p.eatRange('0', '9')) |_| continue;
        if (try p.eat(".")) |_| continue;
        if (try p.eat("_")) |_| continue;
        if (try p.eat("-")) |_| continue;
        break;
    }
}

/// NameStartChar   ::=   ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
fn parseNameStartChar(alloc: std.mem.Allocator, p: *Parser) anyerror!?u21 {
    _ = alloc;
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
fn parseNameChar(alloc: std.mem.Allocator, p: *Parser) anyerror!?u21 {
    if (try p.eatByte('-')) |b| return b;
    if (try p.eatByte('.')) |b| return b;
    if (try p.eatRange('0', '9')) |b| return b;
    if (try parseNameStartChar(alloc, p)) |b| return b;
    if (try p.eatByte(0xB7)) |b| return b;
    if (try p.eatRangeM(0x0300, 0x036F)) |b| return b;
    if (try p.eatRangeM(0x203F, 0x2040)) |b| return b;
    return null;
}

/// SystemLiteral   ::=   ('"' [^"]* '"')
/// SystemLiteral   ::=   ("'" [^']* "'")
fn parseSystemLiteral(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    try p.eat(&.{'"'}) orelse return null;
    try p.skipUntilAfter(&.{'"'});
}

/// PubidLiteral   ::=   '"' PubidChar* '"'
/// PubidLiteral   ::=   "'" (PubidChar - "'")* "'"
fn parsePubidLiteral(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const q = try p.eatQuoteS() orelse return null;
    while (true) {
        const c = try parsePubidChar(alloc, p) orelse break;
        if (q == '\'' and c == q) return;
    }
    try p.eatQuoteE(q) orelse return error.XmlMalformed;
}

/// markupdecl   ::=   elementdecl | AttlistDecl | EntityDecl | NotationDecl | PI | Comment
fn parseMarkupDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    return try parseElementDecl(alloc, p) orelse
        try parseAttlistDecl(alloc, p) orelse
        try parseEntityDecl(alloc, p) orelse
        try parseNotationDecl(alloc, p) orelse
        try parsePI(alloc, p) orelse
        try parseComment(alloc, p) orelse
        null;
}

/// DeclSep   ::=   PEReference | S
fn parseDeclSep(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    return try parsePEReference(alloc, p) orelse
        try parseS(alloc, p) orelse
        null;
}

/// AttValue   ::=   '"' ([^<&"] | Reference)* '"'
/// AttValue   ::=   "'" ([^<&'] | Reference)* "'"
fn parseAttValue(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const q = try p.eatQuoteS() orelse return null;
    while (true) {
        if (try p.eatQuoteE(q)) |_| break;
        if (try p.eatAnyNot(&.{ '<', '&', q })) |_| continue;
        if (try parseReference(alloc, p)) |_| continue;
        unreachable;
    }
}

/// EntityRef   ::=   '&' Name ';'
fn parseEntityRef(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("&") orelse return null;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try p.eat(";") orelse return error.XmlMalformed;
}

/// CharRef   ::=   '&#' [0-9]+ ';'
/// CharRef   ::=   '&#x' [0-9a-fA-F]+ ';'
fn parseCharRef(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    try p.eat("&#x") orelse {
        try p.eat("&#") orelse return null;
        var i: usize = 0;
        while (true) : (i += 1) {
            if (try p.eatRange('0', '9')) |_| continue;
            if (i == 0) return error.XmlMalformed;
            break;
        }
        try p.eat(";") orelse return error.XmlMalformed;
        return;
    };
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try p.eatRange('0', '9')) |_| continue;
        if (try p.eatRange('a', 'f')) |_| continue;
        if (try p.eatRange('A', 'F')) |_| continue;
        if (i == 0) return error.XmlMalformed;
        break;
    }
    try p.eat(";") orelse return error.XmlMalformed;
}

/// CDStart   ::=   '<![CDATA['
fn parseCDStart(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    try p.eat("<![CDATA[") orelse return null;
}

/// CData   ::=   (Char* - (Char* ']]>' Char*))
fn parseCData(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    while (true) {
        if (try p.peek("]]>")) break;
        _ = try parseChar(alloc, p) orelse return error.XmlMalformed;
    }
}

/// CDEnd   ::=   ']]>'
fn parseCDEnd(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    return p.eat("]]>");
}

/// PubidChar   ::=   #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
fn parsePubidChar(alloc: std.mem.Allocator, p: *Parser) anyerror!?u21 {
    _ = alloc;
    if (try p.eatByte(0x20)) |b| return b;
    if (try p.eatByte(0x0D)) |b| return b;
    if (try p.eatByte(0x0A)) |b| return b;
    if (try p.eatRange('a', 'z')) |b| return b;
    if (try p.eatRange('A', 'Z')) |b| return b;
    if (try p.eatRange('0', '9')) |b| return b;
    if (try p.eatAny("-'()+,./:=?;!*#@$_%")) |b| return b;
    return null;
}

/// elementdecl   ::=   '<!ELEMENT' S Name S contentspec S? '>'
fn parseElementDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<!ELEMENT") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseContentSpec(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// AttlistDecl   ::=   '<!ATTLIST' S Name AttDef* S? '>'
fn parseAttlistDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<!ATTLIST") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    while (true) try parseAttDef(alloc, p) orelse break;
    try parseS(alloc, p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// EntityDecl   ::=   GEDecl | PEDecl
fn parseEntityDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<!ENTITY") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    return try parseGEDecl(alloc, p) orelse
        try parsePEDecl(alloc, p) orelse
        return null;
}

/// NotationDecl   ::=   '<!NOTATION' S Name S (ExternalID | PublicID) S? '>'
fn parseNotationDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("<!NOTATION") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseExternalOrPublicID(alloc, p, true) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// PEReference   ::=   '%' Name ';'
fn parsePEReference(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("%") orelse return null;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try p.eat(";") orelse return error.XmlMalformed;
}

/// contentspec   ::=   'EMPTY' | 'ANY' | Mixed | children
fn parseContentSpec(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    if (try p.eat("EMPTY")) |_| return;
    if (try p.eat("ANY")) |_| return;

    try p.eat("(") orelse return null;
    try parseS(alloc, p) orelse {};
    if (try parseMixed(alloc, p)) |_| return;
    if (try parseChildren(alloc, p)) |_| return;
    return null;
}

/// AttDef   ::=   S Name S AttType S DefaultDecl
fn parseAttDef(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseS(alloc, p) orelse return null;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseAttType(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseDefaultDecl(alloc, p) orelse return error.XmlMalformed;
}

/// GEDecl   ::=   '<!ENTITY' S Name S EntityDef S? '>'
fn parseGEDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseName(alloc, p) orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseEntityDef(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// PEDecl   ::=   '<!ENTITY' S '%' S Name S PEDef S? '>'
fn parsePEDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("%") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseName(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parsePEDef(alloc, p) orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try p.eat(">") orelse return error.XmlMalformed;
}

/// Mixed   ::=   '(' S? '#PCDATA' (S? '|' S? Name)* S? ')*'
/// Mixed   ::=   '(' S? '#PCDATA' S? ')'
fn parseMixed(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("#PCDATA") orelse return null;
    try parseS(alloc, p) orelse {};
    if (try p.eat(")")) |_| return;
    while (true) {
        try parseS(alloc, p) orelse {};
        try p.eat("|") orelse break;
        try parseS(alloc, p) orelse {};
        try parseName(alloc, p) orelse return error.XmlMalformed;
    }
    try p.eat(")*") orelse return error.XmlMalformed;
}

/// children   ::=   (choice | seq) ('?' | '*' | '+')?
fn parseChildren(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseChoiceOrSeq(alloc, p, true, null) orelse return null;
    _ = try p.eatAny(&.{ '?', '*', '+' }) orelse {};
}

/// AttType   ::=   StringType | TokenizedType | EnumeratedType
fn parseAttType(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    return try parseStringType(alloc, p) orelse
        try parseTokenizedType(alloc, p) orelse
        try parseEnumeratedType(alloc, p) orelse
        null;
}

/// DefaultDecl   ::=   '#REQUIRED' | '#IMPLIED'
/// DefaultDecl   ::=   (('#FIXED' S)? AttValue)
fn parseDefaultDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    if (try p.eat("#REQUIRED")) |_| return;
    if (try p.eat("#IMPLIED")) |_| return;

    if (try p.eat("#FIXED")) |_| {
        try parseS(alloc, p) orelse return error.XmlMalformed;
    }
    try parseAttValue(alloc, p) orelse return error.XmlMalformed;
}

/// EntityDef   ::=   EntityValue | (ExternalID NDataDecl?)
fn parseEntityDef(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    return try parseEntityValue(alloc, p) orelse {
        try parseExternalOrPublicID(alloc, p, false) orelse return null;
        try parseNDataDecl(alloc, p) orelse {};
        return;
    };
}

/// PEDef   ::=   EntityValue | ExternalID
fn parsePEDef(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    return try parseExternalOrPublicID(alloc, p, false) orelse
        try parseEntityValue(alloc, p) orelse
        null;
}

/// choice   ::=   '(' S? cp ( S? '|' S? cp )+ S? ')'
/// seq      ::=   '(' S? cp ( S? ',' S? cp )* S? ')'
/// cp       ::=   (Name | choice | seq) ('?' | '*' | '+')?
fn parseChoiceOrSeq(alloc: std.mem.Allocator, p: *Parser, started: bool, sep_start: ?u8) anyerror!?void {
    if (!started) {
        try p.eat("(") orelse return null;
        try parseS(alloc, p) orelse {};
        try parseCp(alloc, p, sep_start) orelse return error.XmlMalformed;
    } else {
        try parseCp(alloc, p, sep_start) orelse return null;
    }

    try parseS(alloc, p) orelse {};
    if (try p.eat(")")) |_| return;

    const sep = sep_start orelse try p.eatAny(&.{ '|', ',' }) orelse return error.XmlMalformed;
    if (sep_start != null) _ = try p.eatByte(sep);
    while (true) {
        try parseS(alloc, p) orelse {};
        try parseCp(alloc, p, sep) orelse break;
        try parseS(alloc, p) orelse {};
        _ = try p.eatByte(sep) orelse break;
    }
    try parseS(alloc, p) orelse {};
    try p.eat(")") orelse return error.XmlMalformed;
}

/// StringType   ::=   'CDATA'
fn parseStringType(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    return p.eat("CDATA");
}

/// TokenizedType   ::=   'ID' | 'IDREF' | 'IDREFS' | 'ENTITY' | 'ENTITIES' | 'NMTOKEN' | 'NMTOKENS'
fn parseTokenizedType(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    _ = alloc;
    if (try p.eat("IDREFS")) |_| return;
    if (try p.eat("IDREF")) |_| return;
    if (try p.eat("ID")) |_| return;
    if (try p.eat("ENTITY")) |_| return;
    if (try p.eat("ENTITIES")) |_| return;
    if (try p.eat("NMTOKENS")) |_| return;
    if (try p.eat("NMTOKEN")) |_| return;
    return null;
}

/// EnumeratedType   ::=   NotationType | Enumeration
fn parseEnumeratedType(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    return try parseNotationType(alloc, p) orelse
        try parseEnumeration(alloc, p) orelse
        null;
}

/// EntityValue   ::=   '"' ([^%&"] | PEReference | Reference)* '"'
/// EntityValue   ::=   "'" ([^%&'] | PEReference | Reference)* "'"
fn parseEntityValue(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    const q = try p.eatQuoteS() orelse return null;
    while (true) {
        if (try p.eatQuoteE(q)) |_| break;
        if (try p.eatAnyNot(&.{ '%', '&', q })) |_| continue;
        if (try parsePEReference(alloc, p)) |_| continue;
        if (try parseReference(alloc, p)) |_| continue;
        unreachable;
    }
}

/// NDataDecl   ::=   S 'NDATA' S Name
fn parseNDataDecl(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try parseS(alloc, p) orelse return null;
    try p.eat("NDATA") orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try parseName(alloc, p) orelse return error.XmlMalformed;
}

/// cp   ::=   (Name | choice | seq) ('?' | '*' | '+')?
fn parseCp(alloc: std.mem.Allocator, p: *Parser, sep_start: ?u8) anyerror!?void {
    try parseName(alloc, p) orelse try parseChoiceOrSeq(alloc, p, false, sep_start) orelse return null;
    _ = try p.eatAny(&.{ '?', '*', '+' }) orelse {};
}

/// NotationType   ::=   'NOTATION' S '(' S? Name (S? '|' S? Name)* S? ')'
fn parseNotationType(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("NOTATION") orelse return null;
    try parseS(alloc, p) orelse return error.XmlMalformed;
    try p.eat("(") orelse return error.XmlMalformed;
    try parseS(alloc, p) orelse {};
    try parseName(alloc, p) orelse return error.XmlMalformed;
    while (true) {
        try parseS(alloc, p) orelse {};
        try p.eat("|") orelse break;
        try parseS(alloc, p) orelse {};
        try parseName(alloc, p) orelse return error.XmlMalformed;
    }
    try parseS(alloc, p) orelse {};
    try p.eat(")") orelse return error.XmlMalformed;
}

/// Enumeration   ::=   '(' S? Nmtoken (S? '|' S? Nmtoken)* S? ')'
fn parseEnumeration(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    try p.eat("(") orelse return null;
    try parseS(alloc, p) orelse {};
    try parseNmtoken(alloc, p) orelse return error.XmlMalformed;
    while (true) {
        try parseS(alloc, p) orelse {};
        _ = try p.eatByte('|') orelse break;
        try parseS(alloc, p) orelse {};
        try parseNmtoken(alloc, p) orelse return error.XmlMalformed;
    }
    try parseS(alloc, p) orelse {};
    try p.eat(")") orelse return error.XmlMalformed;
}

/// Nmtoken   ::=   (NameChar)+
fn parseNmtoken(alloc: std.mem.Allocator, p: *Parser) anyerror!?void {
    var i: usize = 0;
    while (true) : (i += 1) {
        if (try parseNameChar(alloc, p)) |_| continue;
        if (i == 0) return null;
        break;
    }
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
