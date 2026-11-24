@testable import DontBurnCore
import Foundation

/// Made-up settings files, the cases of the spike's self-test in
/// `Spikes/claude-hook/profile-step.sh`.
enum SettingsSample {
    /// Two-space JSON with another tool's hook, as Claude Code writes it.
    static let otherHook = lines(
        "{",
        "  \"model\": \"opus\",",
        "  \"permissions\": {",
        "    \"allow\": [",
        "      \"Bash(git status)\"",
        "    ]",
        "  },",
        "  \"hooks\": {",
        "    \"Stop\": [",
        "      {",
        "        \"hooks\": [",
        "          {",
        "            \"type\": \"command\",",
        "            \"command\": \"~/bin/acme-notify\"",
        "          }",
        "        ]",
        "      }",
        "    ]",
        "  }",
        "}",
    )
    /// No `hooks` key, and no newline at the end.
    static let noNewline = Data("{\n  \"theme\": \"dark\",\n  \"env\": {\n    \"ACME_REGION\": \"eu\"\n  }\n}".utf8)
    /// `"hooks": {}`.
    static let emptyHooks = lines("{", "  \"hooks\": {}", "}")
    /// An empty object.
    static let emptyObject = lines("{}")
    /// Zero bytes.
    static let zeroBytes = Data()
    /// An event list that was there, empty, before the install.
    static let emptyStopList = lines("{", "  \"hooks\": {", "    \"Stop\": []", "  }", "}")
    /// Another tool's hook on an event the app does not install for.
    static let otherEvent = lines(
        "{",
        "  \"hooks\": {",
        "    \"PreToolUse\": [",
        "      {",
        "        \"matcher\": \"Bash\",",
        "        \"hooks\": [",
        "          {",
        "            \"type\": \"command\",",
        "            \"command\": \"~/bin/globex-guard\"",
        "          }",
        "        ]",
        "      }",
        "    ]",
        "  },",
        "  \"theme\": \"light\"",
        "}",
    )
    /// Four spaces and a hook on one line, as a person may write it.
    static let handFormatted = lines(
        "{",
        "    \"theme\": \"dark\",",
        "    \"hooks\": { \"Stop\": [ { \"hooks\": [ { \"type\": \"command\", "
            + "\"command\": \"~/bin/globex-bell\" } ] } ] }",
        "}",
    )
    /// `"hooks": []`.
    static let hooksList = lines("{", "  \"hooks\": []", "}")
    /// `"hooks": null`.
    static let hooksNull = lines("{", "  \"hooks\": null", "}")

    /// Every file that installs and uninstalls back to the same bytes.
    static let installable: [Data] = [
        otherHook, noNewline, emptyHooks, emptyObject, zeroBytes, emptyStopList, otherEvent,
    ]

    /// `text` as a file: each line followed by a newline.
    static func lines(_ text: String...) -> Data {
        Data(text.map { $0 + "\n" }.joined().utf8)
    }

    /// The text of `data`, or nothing when it is not UTF-8.
    static func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    /// `data` with `key` set to `value` at the top, written two-space as Claude Code would.
    static func setting(_ key: String, to value: JSONValue, in data: Data) throws -> Data {
        var members = try JSONValue(parsing: data).members ?? []
        members[key] = value
        let newline = data.last == UInt8(ascii: "\n") ? "\n" : ""
        return Data((JSONValue.object(members).formatted + newline).utf8)
    }

    /// How many hooks in the settings `data` run exactly `command`.
    static func hooks(running command: String, in data: Data) -> Int {
        HookSettings.commands(in: data).count { $0 == command }
    }
}
