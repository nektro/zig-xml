# zig-xml

![loc](https://sloc.xyz/github/nektro/zig-xml)
[![license](https://img.shields.io/github/license/nektro/zig-xml.svg)](https://github.com/nektro/zig-xml/blob/master/LICENSE)
[![nektro @ github sponsors](https://img.shields.io/badge/sponsors-nektro-purple?logo=github)](https://github.com/sponsors/nektro)
[![Zig](https://img.shields.io/badge/Zig-0.14-f7a41d)](https://ziglang.org/)
[![Zigmod](https://img.shields.io/badge/Zigmod-latest-f7a41d)](https://github.com/nektro/zigmod)

A pure-zig spec-compliant XML parser.

https://www.w3.org/TR/xml/

Passes all standalone tests from https://www.w3.org/XML/Test/xmlconf-20020606.htm, even more coverage coming soon.

One caveat is that this parser expects UTF-8.

```
Build Summary: 3/3 steps succeeded; 120/120 tests passed
test success
└─ run test 120 passed 5ms MaxRSS:1M
   └─ zig test Debug native success 1s MaxRSS:247M
```
