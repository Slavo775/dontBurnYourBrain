@testable import DontBurnCore
import Foundation
import Testing

private let toolPath = "/Applications/DontBurn.app/Contents/Helpers/dontburn-hook"
private let command = "'\(toolPath)'"

private func installing(into data: Data) throws -> HookSettingsEdit {
    try HookSettings.installing(command: command, marker: "dontburn-hook", into: data)
}

private func uninstalling(_ edit: HookSettingsEdit, from data: Data) throws -> Data {
    try HookSettings.uninstalling(
        command: command,
        createdHooks: edit.createdHooks,
        createdEvents: edit.createdEvents,
        wasEmpty: edit.wasEmpty,
        from: data,
    )
}

// MARK: - Install, then uninstall

@Test(arguments: SettingsSample.installable)
func `install then uninstall gives back the same bytes`(original: Data) throws {
    let edit = try installing(into: original)

    #expect(edit.data != original)
    #expect(try uninstalling(edit, from: edit.data) == original)
}

@Test(arguments: SettingsSample.installable)
func `install adds one hook for each handled event, in a file that passes its own check`(original: Data) throws {
    let edit = try installing(into: original)
    let hooks = try #require(JSONValue(parsing: edit.data).members?["hooks"]?.members)

    #expect(try HookSettings.checked(edit.data) == edit.data)
    #expect(SettingsSample.hooks(running: command, in: edit.data) == HookEvent.handledNames.count)
    for event in HookEvent.handledNames {
        #expect(hooks[event]?.values?.last == HookSettings.group(command: command))
    }
}

@Test func `install keeps another tool's hook first and every other key as it was`() throws {
    let edit = try installing(into: SettingsSample.otherHook)
    let members = try #require(JSONValue(parsing: edit.data).members)
    let stop = try #require(members["hooks"]?.members?["Stop"]?.values)

    #expect(members.map(\.key) == ["model", "permissions", "hooks"])
    #expect(members["model"] == .string("opus"))
    #expect(stop.count == 2)
    #expect(HookSettings.commands(in: edit.data).first == "~/bin/acme-notify")
    #expect(members["hooks"]?.members?.map(\.key) == ["Stop"] + HookEvent.handledNames.filter { $0 != "Stop" })
}

@Test func `install records what it created`() throws {
    let other = try installing(into: SettingsSample.otherHook)
    let none = try installing(into: SettingsSample.noNewline)
    let empty = try installing(into: SettingsSample.emptyHooks)

    #expect(!other.createdHooks)
    #expect(other.createdEvents == HookEvent.handledNames.filter { $0 != "Stop" })
    #expect(none.createdHooks)
    #expect(none.createdEvents == HookEvent.handledNames)
    #expect(!empty.createdHooks)
    #expect(empty.createdEvents == HookEvent.handledNames)
    #expect(!other.wasEmpty && !none.wasEmpty && !empty.wasEmpty)
}

@Test func `install keeps whether the file ends with a newline`() throws {
    #expect(try installing(into: SettingsSample.otherHook).data.last == UInt8(ascii: "\n"))
    #expect(try installing(into: SettingsSample.noNewline).data.last == UInt8(ascii: "}"))
}

@Test func `a file of zero bytes counts as an empty object and gets zero bytes back`() throws {
    let edit = try installing(into: SettingsSample.zeroBytes)

    #expect(edit.wasEmpty)
    #expect(edit.createdHooks)
    #expect(edit.data.first == UInt8(ascii: "{"))
    #expect(edit.data.last == UInt8(ascii: "}"))
    #expect(try uninstalling(edit, from: edit.data).isEmpty)
}

@Test func `a group the hook was added to by hand is not the app's own and stays`() throws {
    let edit = try installing(into: SettingsSample.emptyHooks)
    var members = try #require(JSONValue(parsing: edit.data).members)
    var hooks = try #require(members["hooks"]?.members)
    // One group that runs the app's command next to another tool's.
    let mixed = JSONValue.object([JSONMember("hooks", .array([
        .object([JSONMember("type", .string("command")), JSONMember("command", .string(command))]),
        .object([JSONMember("type", .string("command")), JSONMember("command", .string("~/bin/acme-notify"))]),
    ]))])
    hooks["SessionStart"] = .array((hooks["SessionStart"]?.values ?? []) + [mixed])
    members["hooks"] = .object(hooks)
    let changed = Data((JSONValue.object(members).formatted + "\n").utf8)

    let after = try uninstalling(edit, from: changed)
    let sessionStart = try #require(JSONValue(parsing: after).members?["hooks"]?.members?["SessionStart"])

    #expect(sessionStart == .array([mixed]))
    #expect(SettingsSample.hooks(running: command, in: after) == 1)
}

@Test func `a list the install created stays while another group is in it`() throws {
    let edit = try installing(into: SettingsSample.emptyHooks)
    var members = try #require(JSONValue(parsing: edit.data).members)
    var hooks = try #require(members["hooks"]?.members)
    let globex = HookSettings.group(command: "~/bin/globex-bell")
    hooks["Notification"] = .array((hooks["Notification"]?.values ?? []) + [globex])
    members["hooks"] = .object(hooks)
    let changed = Data((JSONValue.object(members).formatted + "\n").utf8)

    let after = try uninstalling(edit, from: changed)

    #expect(try JSONValue(parsing: after).members?["hooks"] == .object([JSONMember("Notification", .array([globex]))]))
}

@Test func `a change made while installed is kept by the uninstall`() throws {
    let edit = try installing(into: SettingsSample.otherHook)
    let changed = try SettingsSample.setting("model", to: .string("sonnet"), in: edit.data)

    let after = try uninstalling(edit, from: changed)

    #expect(SettingsSample.hooks(running: command, in: after) == 0)
    #expect(try JSONValue(parsing: after).members?["model"] == .string("sonnet"))
    #expect(HookSettings.differingKeys(after, from: SettingsSample.otherHook) == ["model"])
}

@Test func `a key added to a file that had zero bytes is kept as two-space JSON`() throws {
    let edit = try installing(into: SettingsSample.zeroBytes)
    let changed = try SettingsSample.setting("theme", to: .string("dark"), in: edit.data)

    let after = try uninstalling(edit, from: changed)

    #expect(SettingsSample.text(after) == "{\n  \"theme\": \"dark\"\n}")
}

@Test(arguments: [SettingsSample.otherHook, SettingsSample.zeroBytes, SettingsSample.emptyObject])
func `uninstall leaves a file that holds none of the app's groups as it is`(data: Data) throws {
    let edit = try installing(into: SettingsSample.noNewline)

    #expect(try uninstalling(edit, from: data) == data)
}

// MARK: - Refusals

@Test(arguments: [
    (SettingsSample.handFormatted, HookInstallError.unusualFormatting),
    (Data("{\"theme\":\"dark\"}\n".utf8), .unusualFormatting),
    (Data("{\n  \"theme\": \"dark\"\n}\n\n".utf8), .unusualFormatting),
    (Data("{\r\n  \"theme\": \"dark\"\r\n}\r\n".utf8), .unusualFormatting),
    (Data("{\n  \"name\": \"\\u00e9\"\n}\n".utf8), .unusualFormatting),
    (Data("{\n  \"path\": \"a\\/b\"\n}\n".utf8), .unusualFormatting),
    (SettingsSample.hooksList, .hooksNotObjectOfLists),
    (SettingsSample.hooksNull, .hooksNotObjectOfLists),
    (SettingsSample.lines("{", "  \"hooks\": {", "    \"Stop\": {}", "  }", "}"), .hooksNotObjectOfLists),
    (
        SettingsSample.lines("{", "  \"hooks\": {", "    \"Stop\": [", "      1", "    ]", "  }", "}"),
        .hooksNotObjectOfLists,
    ),
    (SettingsSample.lines("[]"), .notJSONObject),
    (SettingsSample.lines("\"Acme\""), .notJSONObject),
    (Data("not json\n".utf8), .notJSONObject),
    (Data("{\"a\": 1, \"a\": 2}".utf8), .notJSONObject),
    (Data([0x7B, 0xFF, 0x7D]), .notJSONObject),
    (Data(" ".utf8), .notJSONObject),
])
func `a file the installer may not edit is refused`(data: Data, error: HookInstallError) {
    #expect(throws: error) { try HookSettings.checked(data) }
    #expect(throws: error) { try installing(into: data) }
    #expect(throws: error) { try uninstalling(installing(into: SettingsSample.emptyHooks), from: data) }
}

@Test func `a file above the size limit is refused before it is read as JSON`() {
    let data = Data(repeating: UInt8(ascii: " "), count: HookSettings.maximumSize + 1)

    #expect(throws: HookInstallError.tooLarge) { try HookSettings.checked(data) }
    #expect(throws: HookInstallError.tooLarge) { try installing(into: data) }
}

@Test func `zero bytes pass the check`() throws {
    #expect(try HookSettings.checked(Data()) == Data())
}

@Test func `a file that holds the hook already is refused, in any spelling of its path`() throws {
    let installed = try installing(into: SettingsSample.otherHook).data
    let byHand = try SettingsSample.setting(
        "hooks",
        to: .object([
            JSONMember("Stop", .array([HookSettings.group(command: "/opt/acme/dontburn-hook --target dev")])),
        ]),
        in: SettingsSample.emptyObject,
    )

    #expect(throws: HookInstallError.alreadyInstalled) { try installing(into: installed) }
    #expect(throws: HookInstallError.alreadyInstalled) { try installing(into: byHand) }
}

// MARK: - Reading commands and keys

@Test func `commands are found in any formatting`() {
    #expect(HookSettings.commands(in: SettingsSample.handFormatted) == ["~/bin/globex-bell"])
    #expect(HookSettings.commands(in: SettingsSample.otherHook) == ["~/bin/acme-notify"])
}

@Test(arguments: [
    Data(), Data("not json".utf8), SettingsSample.lines("[]"), SettingsSample.hooksList, SettingsSample.hooksNull,
])
func `text that holds no hooks object has no commands`(data: Data) {
    #expect(HookSettings.commands(in: data).isEmpty)
}

@Test func `a hook without a command string has no command`() {
    let hooks = #"[{"type": "command", "command": 5}, {"type": "prompt"}, 1]"#
    let data = Data(#"{"hooks": {"Stop": [{"hooks": \#(hooks)}]}}"#.utf8)

    #expect(HookSettings.commands(in: data).isEmpty)
}

@Test func `differing keys name the changed top-level keys, those of the file first`() {
    let before = SettingsSample.lines("{", "  \"model\": \"opus\",", "  \"theme\": \"dark\",", "  \"env\": {}", "}")
    let now = SettingsSample.lines(
        "{", "  \"verbose\": true,", "  \"model\": \"sonnet\",", "  \"theme\": \"dark\"", "}",
    )

    #expect(HookSettings.differingKeys(now, from: before) == ["verbose", "model", "env"])
    #expect(HookSettings.differingKeys(before, from: before) == [])
}

@Test func `differing keys count zero bytes as an empty object and give nil for other text`() {
    #expect(HookSettings.differingKeys(Data(), from: SettingsSample.emptyObject) == [])
    #expect(HookSettings.differingKeys(SettingsSample.noNewline, from: Data()) == ["theme", "env"])
    #expect(HookSettings.differingKeys(Data("not json".utf8), from: Data()) == nil)
    #expect(HookSettings.differingKeys(Data(), from: SettingsSample.lines("[]")) == nil)
}

@Test func `differing keys tell apart two keys that differ only in Unicode normalization`() throws {
    let composed = "\u{E9}"
    let decomposed = "e\u{301}"
    let before = SettingsSample.lines("{", "  \"\(composed)\": 1", "}")
    let both = SettingsSample.lines("{", "  \"\(composed)\": 1,", "  \"\(decomposed)\": 1", "}")
    let other = SettingsSample.lines("{", "  \"\(decomposed)\": 1", "}")

    let added = try #require(HookSettings.differingKeys(both, from: before))
    let swapped = try #require(HookSettings.differingKeys(other, from: before))

    #expect(added.map { Array($0.utf8) } == [Array(decomposed.utf8)])
    #expect(swapped.map { Array($0.utf8) } == [Array(decomposed.utf8), Array(composed.utf8)])
}

@Test func `a file with keys that differ only in Unicode normalization comes back byte for byte`() throws {
    let original = SettingsSample.lines("{", "  \"\u{E9}\": 1,", "  \"e\u{301}\": 2", "}")

    let edit = try installing(into: original)

    #expect(try uninstalling(edit, from: edit.data) == original)
}

// MARK: - The lines and the group

@Test func `the group runs the command with a timeout`() {
    #expect(HookSettings.group(command: command).formatted == """
    {
      "hooks": [
        {
          "type": "command",
          "command": "'\(toolPath)'",
          "timeout": 5
        }
      ]
    }
    """)
}

@Test func `the lines to add by hand are a two-space settings file with one group per handled event`() throws {
    let lines = Data(HookSettings.manualLines(command: command).utf8)
    let hooks = try #require(JSONValue(parsing: lines).members?["hooks"]?.members)

    #expect(try HookSettings.checked(lines) == lines)
    #expect(hooks.map(\.key) == HookEvent.handledNames)
    #expect(hooks.allSatisfy { $0.value == .array([HookSettings.group(command: command)]) })
}

@Test func `the handled events are the nine the session store acts on`() {
    #expect(HookEvent.handledNames == [
        "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop",
        "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd",
    ])
}

// MARK: - The command

@Test func `the release command is the quoted path alone, and dev adds its target`() throws {
    let release = try HookCommand(toolPath: toolPath, target: .release)
    let dev = try HookCommand(toolPath: toolPath, target: .dev)

    #expect(release.text == "'\(toolPath)'")
    #expect(dev.text == "'\(toolPath)' --target dev")
    #expect(release.toolName == "dontburn-hook")
    #expect(dev.toolPath == toolPath)
}

@Test(arguments: [
    "/Volumes/Acme Tools/dontburn-hook",
    "/opt/$HOME/dontburn-hook",
    "/opt/`id`/dontburn-hook",
    "/opt/it's/dontburn-hook",
    "/opt/a\"b\\c;d|e&f*g?(h)/dontburn-hook",
])
func `the shell reads back exactly the tool's path, whatever it holds`(path: String) throws {
    let command = try HookCommand(toolPath: path, target: .dev)
    let shell = Process()
    let output = Pipe()
    shell.executableURL = URL(filePath: "/bin/sh")
    shell.arguments = ["-c", "printf '%s\\n' \(command.text)"]
    shell.environment = [:]
    shell.standardOutput = output
    try shell.run()
    shell.waitUntilExit()
    let printed = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

    #expect(printed == "\(path)\n--target\ndev\n")
    #expect(command.toolName == "dontburn-hook")
}

@Test(arguments: [
    "", "/", "dontburn-hook", "Helpers/dontburn-hook", "~/bin/dontburn-hook",
    "/opt/acme\n/dontburn-hook", "/opt/acme\t/dontburn-hook", "/opt/acme\u{7F}/dontburn-hook",
    "/opt/\u{1B}[31m/dontburn-hook",
])
func `a tool path that is not absolute or holds a control character is refused`(path: String) {
    #expect(throws: HookInstallError.unsafeToolPath) { try HookCommand(toolPath: path, target: .release) }
}

// MARK: - Errors

@Test func `only refusals about the file offer the lines to change by hand`() {
    let offers: [HookInstallError] = [
        .missing, .notAFile, .unreadable, .tooLarge, .notJSONObject, .unusualFormatting, .hooksNotObjectOfLists,
        .writeFailed,
    ]
    let others: [HookInstallError] = [
        .alreadyInstalled, .notInstalled, .outsideAllowedFolder, .changedMeanwhile, .unsafeToolPath, .toolMissing,
    ]

    #expect(offers.allSatisfy { $0.offersManualLines })
    #expect(!others.contains { $0.offersManualLines })
}
