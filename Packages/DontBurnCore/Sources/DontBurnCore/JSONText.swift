import Foundation

// Foundation's `JSONSerialization` forgets the order of an object's keys, so it
// cannot write a settings file back byte for byte. This small value keeps that
// order and each number as it was written, and writes two-space JSON the way
// Node's `JSON.stringify(value, null, 2)` does, which is how Claude Code writes
// its settings. A file it does not write back byte for byte is refused by the
// installer, so a gap here fails safe as a refusal and never changes a file.

/// A JSON value that keeps the order of an object's keys and every number as written.
public enum JSONValue: Equatable, Sendable {
    /// An object, its members in the order they were written.
    case object([JSONMember])
    /// An array.
    case array([JSONValue])
    /// A string.
    case string(String)
    /// A number, as written, such as `5` or `1.0e3`.
    case number(String)
    /// `true` or `false`.
    case bool(Bool)
    /// `null`.
    case null

    /// The value `data` holds as JSON text.
    ///
    /// Strict JSON: no comments, no trailing commas, and only whitespace
    /// around the value. Throws ``JSONTextError`` when `data` is not valid
    /// UTF-8 JSON, nests deeper than ``maximumDepth``, or repeats a key in one object.
    public init(parsing data: Data) throws {
        var parser = JSONParser(bytes: Array(data))
        self = try parser.document()
    }

    /// The deepest nesting ``init(parsing:)`` accepts.
    public static let maximumDepth = 256

    /// The value as two-space JSON with no newline at the end, as
    /// `JSON.stringify(value, null, 2)` writes it.
    public var formatted: String {
        var text = ""
        write(into: &text, indent: "")
        return text
    }

    private func write(into text: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case let .object(members) where members.isEmpty: text += "{}"
        case let .array(values) where values.isEmpty: text += "[]"
        case let .object(members):
            text += "{\n"
            for (offset, member) in members.enumerated() {
                text += inner
                Self.quote(member.key, into: &text)
                text += ": "
                member.value.write(into: &text, indent: inner)
                text += offset < members.count - 1 ? ",\n" : "\n"
            }
            text += indent + "}"
        case let .array(values):
            text += "[\n"
            for (offset, value) in values.enumerated() {
                text += inner
                value.write(into: &text, indent: inner)
                text += offset < values.count - 1 ? ",\n" : "\n"
            }
            text += indent + "]"
        case let .string(string): Self.quote(string, into: &text)
        case let .number(number): text += number
        case let .bool(bool): text += bool ? "true" : "false"
        case .null: text += "null"
        }
    }

    /// `string` in quotes, escaped as `JSON.stringify` escapes it.
    private static func quote(_ string: String, into text: inout String) {
        text += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case _ where scalar.value < 0x20: text += String(format: "\\u%04x", scalar.value)
            default: text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }

    /// The members of an object, or `nil` for any other value.
    public var members: [JSONMember]? {
        if case let .object(members) = self {
            members
        } else {
            nil
        }
    }

    /// The values of an array, or `nil` for any other value.
    public var values: [JSONValue]? {
        if case let .array(values) = self {
            values
        } else {
            nil
        }
    }
}

/// One key of a JSON object and its value.
public struct JSONMember: Equatable, Sendable {
    /// The key.
    public var key: String
    /// The value.
    public var value: JSONValue

    /// The member `key` with `value`.
    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

extension [JSONMember] {
    /// The value of the first member named `key`. Setting `nil` removes the
    /// member, and setting a new key adds it at the end, as JavaScript does.
    subscript(key: String) -> JSONValue? {
        get { first { $0.key == key }?.value }
        set {
            guard let index = firstIndex(where: { $0.key == key }) else {
                if let newValue {
                    append(JSONMember(key, newValue))
                }
                return
            }
            if let newValue {
                self[index].value = newValue
            } else {
                remove(at: index)
            }
        }
    }
}

/// Why JSON text could not be read.
public enum JSONTextError: Error, Equatable, Sendable {
    /// The text is not valid JSON in UTF-8.
    case invalid
    /// One object holds the same key twice.
    case repeatedKey
    /// The values nest deeper than ``JSONValue/maximumDepth``.
    case tooDeep
}

/// Reads JSON text byte by byte. Only ``JSONValue/init(parsing:)`` uses it.
private struct JSONParser {
    let bytes: [UInt8]
    var index = 0

    mutating func document() throws -> JSONValue {
        skipWhitespace()
        let value = try value(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw JSONTextError.invalid }
        return value
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func skipWhitespace() {
        while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
            index += 1
        }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard current == byte else { throw JSONTextError.invalid }
        index += 1
    }

    private mutating func value(depth: Int) throws -> JSONValue {
        guard depth < JSONValue.maximumDepth else { throw JSONTextError.tooDeep }
        switch current {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return try .string(string())
        case UInt8(ascii: "t"): try literal("true")
            return .bool(true)
        case UInt8(ascii: "f"): try literal("false")
            return .bool(false)
        case UInt8(ascii: "n"): try literal("null")
            return .null
        default: return try .number(number())
        }
    }

    private mutating func literal(_ word: String) throws {
        for byte in word.utf8 {
            try expect(byte)
        }
    }

    private mutating func object(depth: Int) throws -> JSONValue {
        try expect(UInt8(ascii: "{"))
        skipWhitespace()
        var members: [JSONMember] = []
        if current == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        var keys: Set<String> = []
        while true {
            skipWhitespace()
            let key = try string()
            guard keys.insert(key).inserted else { throw JSONTextError.repeatedKey }
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            skipWhitespace()
            try members.append(JSONMember(key, value(depth: depth + 1)))
            skipWhitespace()
            if current == UInt8(ascii: ",") {
                index += 1
            } else {
                try expect(UInt8(ascii: "}"))
                return .object(members)
            }
        }
    }

    private mutating func array(depth: Int) throws -> JSONValue {
        try expect(UInt8(ascii: "["))
        skipWhitespace()
        var values: [JSONValue] = []
        if current == UInt8(ascii: "]") {
            index += 1
            return .array(values)
        }
        while true {
            skipWhitespace()
            try values.append(value(depth: depth + 1))
            skipWhitespace()
            if current == UInt8(ascii: ",") {
                index += 1
            } else {
                try expect(UInt8(ascii: "]"))
                return .array(values)
            }
        }
    }

    private mutating func string() throws -> String {
        try expect(UInt8(ascii: "\""))
        var utf8: [UInt8] = []
        while let byte = current {
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                guard let string = String(validating: utf8, as: UTF8.self) else { throw JSONTextError.invalid }
                return string
            case UInt8(ascii: "\\"): try utf8.append(contentsOf: String(escape()).utf8)
            case ..<0x20: throw JSONTextError.invalid
            default: utf8.append(byte)
            }
        }
        throw JSONTextError.invalid
    }

    /// The escapes of one character after the backslash, all but `\u`.
    private static let shortEscapes: [UInt8: Unicode.Scalar] = [
        UInt8(ascii: "\""): "\"", UInt8(ascii: "\\"): "\\", UInt8(ascii: "/"): "/", UInt8(ascii: "b"): "\u{08}",
        UInt8(ascii: "f"): "\u{0C}", UInt8(ascii: "n"): "\n", UInt8(ascii: "r"): "\r", UInt8(ascii: "t"): "\t",
    ]

    /// The character after a backslash, which has been read already.
    private mutating func escape() throws -> Unicode.Scalar {
        guard let byte = current else { throw JSONTextError.invalid }
        index += 1
        if let scalar = Self.shortEscapes[byte] {
            return scalar
        }
        guard byte == UInt8(ascii: "u") else { throw JSONTextError.invalid }
        let unit = try hexUnit()
        guard (0xD800 ..< 0xDC00).contains(unit) else {
            guard let scalar = Unicode.Scalar(unit) else { throw JSONTextError.invalid }
            return scalar
        }
        // A high surrogate must be followed by its low one.
        try expect(UInt8(ascii: "\\"))
        try expect(UInt8(ascii: "u"))
        let low = try hexUnit()
        guard (0xDC00 ..< 0xE000).contains(low),
              let scalar = Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
        else { throw JSONTextError.invalid }
        return scalar
    }

    /// Four hex digits, ASCII only.
    private mutating func hexUnit() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw JSONTextError.invalid }
        var unit: UInt32 = 0
        for byte in bytes[index ..< index + 4] {
            guard byte < 0x80, let digit = UInt32(String(Unicode.Scalar(byte)), radix: 16) else {
                throw JSONTextError.invalid
            }
            unit = unit << 4 | digit
        }
        index += 4
        return unit
    }

    /// A number as written: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`.
    private mutating func number() throws -> String {
        let start = index
        if current == UInt8(ascii: "-") {
            index += 1
        }
        if current == UInt8(ascii: "0") {
            index += 1
        } else {
            try digits()
        }
        if current == UInt8(ascii: ".") {
            index += 1
            try digits()
        }
        if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
            index += 1
            if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") {
                index += 1
            }
            try digits()
        }
        // Only ASCII was read, which is always valid UTF-8.
        return String(validating: bytes[start ..< index], as: UTF8.self) ?? ""
    }

    /// One or more ASCII digits.
    private mutating func digits() throws {
        let start = index
        while let byte = current, (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) {
            index += 1
        }
        guard index > start else { throw JSONTextError.invalid }
    }
}
