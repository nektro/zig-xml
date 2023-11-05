# zig-xml

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

## License

MPL-2.0
