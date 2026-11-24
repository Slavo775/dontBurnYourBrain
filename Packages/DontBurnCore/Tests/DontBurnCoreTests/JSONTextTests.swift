@testable import DontBurnCore
import Foundation
import Testing

private func parsed(_ text: String) throws -> JSONValue {
    try JSONValue(parsing: Data(text.utf8))
}

// MARK: - Round trips

/// Each text is what Node's `JSON.stringify(value, null, 2)` writes for it.
@Test(arguments: [
    "{}",
    "[]",
    "{\n  \"model\": \"opus\"\n}",
    "{\n  \"a\": \"q\\\"b\\\\s/\\b\\f\\n\\r\\t\\u0001\\u001f\u{7F} é 😀\",\n"
        + "  \"b\": [\n    1,\n    {\n      \"c\": []\n    },\n    {}\n  ],\n"
        + "  \"d\": {\n    \"e\": null,\n    \"f\": true,\n    \"g\": false,\n    \"h\": -0.5\n  }\n}",
    "[\n  [\n    [\n      \"Acme\"\n    ]\n  ],\n  \"Globex\"\n]",
    "\"Personal\"",
    "42",
    "null",
])
func `two-space JSON comes back byte for byte`(text: String) throws {
    #expect(try parsed(text).formatted == text)
}

@Test(arguments: ["0", "-0", "1.50", "1.0e3", "1E+2", "-2e-7", "123456789012345678901234567890"])
func `a number keeps the form it was written in`(number: String) throws {
    let value = try parsed("[\(number)]")

    #expect(value == .array([.number(number)]))
    #expect(value.formatted == "[\n  \(number)\n]")
}

@Test func `members keep the order they were written in`() throws {
    let value = try parsed(#"{"globex": 1, "acme": 2, "personal": 3}"#)

    #expect(value.members?.map(\.key) == ["globex", "acme", "personal"])
}

@Test func `whitespace around the value is allowed`() throws {
    let expected = JSONValue.object([JSONMember("a", .array([.number("1"), .number("2")]))])

    #expect(try parsed(" \t\r\n{ \"a\" : [ 1 , 2 ] }\n ") == expected)
}

@Test func `escapes are read as the characters they stand for`() throws {
    let value = try parsed(#"["\u00e9\/\ud83d\ude00\u0041"]"#)

    #expect(value == .array([.string("é/😀A")]))
}

@Test func `an escaped form that JSON.stringify never writes does not come back byte for byte`() throws {
    let text = "[\n  \"\\u00e9\\/\"\n]"

    #expect(try parsed(text).formatted != text)
}

// MARK: - Refusals

@Test(arguments: [
    "", " ", "{", "}", "[", "{\"a\":}", "{\"a\":1,}", "[1,]", "[1 2]", "{\"a\" 1}", "{1:2}", "{'a':1}",
    "// note\n{}", "/* note */{}", "{} {}", "{}x", "01", "1.", ".5", "-", "+1", "1e", "1e+", "0x10",
    "NaN", "Infinity", "tru", "nul", "fals", "\"open", "\"a\tb\"", "\"a\nb\"", "\"\\x\"", "\"\\u12\"",
    "\"\\uZZZZ\"", "\"\\udc00\"", "\"\\ud800x\"", "\"\\ud800\\u0041\"", "\"\\ud800\\x\"", "\"\\", "\u{FEFF}{}",
])
func `text outside strict JSON is refused`(text: String) {
    #expect(throws: JSONTextError.invalid) { try parsed(text) }
}

@Test func `hex digits must be ASCII`() {
    // A fullwidth digit in place of the last hex digit.
    #expect(throws: JSONTextError.invalid) { try parsed("\"\\u004\u{FF11}\"") }
}

@Test func `invalid UTF-8 in a string is refused`() {
    #expect(throws: JSONTextError.invalid) {
        try JSONValue(parsing: Data([0x22, 0xFF, 0xFE, 0x22]))
    }
    #expect(throws: JSONTextError.invalid) {
        try JSONValue(parsing: Data([0x7B, 0x22, 0xC3, 0x22, 0x3A, 0x31, 0x7D]))
    }
}

@Test func `a key repeated in one object is refused`() {
    #expect(throws: JSONTextError.repeatedKey) { try parsed(#"{"a": 1, "a": 2}"#) }
    #expect(throws: JSONTextError.repeatedKey) { try parsed(#"{"hooks": {"Stop": [], "Stop": []}}"#) }
}

@Test func `the same key in two objects is allowed`() throws {
    let value = try parsed(#"[{"a": 1}, {"a": 2}]"#)

    #expect(value.values?.count == 2)
}

@Test func `nesting is accepted down to the maximum depth and refused below it`() throws {
    let depth = JSONValue.maximumDepth
    let deepest = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    let tooDeep = "[" + deepest + "]"

    #expect(try parsed(deepest).values != nil)
    #expect(throws: JSONTextError.tooDeep) { try parsed(tooDeep) }
}

// MARK: - Members and values

@Test func `members and values are nil for any other kind of value`() {
    let others: [JSONValue] = [.string("Acme"), .number("1"), .bool(true), .null]

    for value in others {
        #expect(value.members == nil)
        #expect(value.values == nil)
    }
    #expect(JSONValue.array([]).members == nil)
    #expect(JSONValue.object([]).values == nil)
}

@Test func `setting a member replaces it in place, adds a new one at the end, and nil removes it`() {
    var members = [JSONMember("acme", .number("1")), JSONMember("globex", .number("2"))]

    members["acme"] = .number("3")
    members["personal"] = .number("4")
    members["globex"] = nil
    members["missing"] = nil

    #expect(members == [JSONMember("acme", .number("3")), JSONMember("personal", .number("4"))])
    #expect(members["personal"] == .number("4"))
    #expect(members["globex"] == nil)
}
