@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// Each command as a short phrase, so a test names what it expects in one string.
private func phrase(_ command: BarCommand) -> String {
    switch command {
    case let .start(workspace, minutes): "start \(workspace.name)" + (minutes.map { " for \($0)" } ?? "")
    case .pause: "pause"
    case .resume: "resume"
    case let .takeBreak(minutes): "break" + (minutes.map { " \($0)" } ?? "")
    case .extend: "+15"
    case .end: "end"
    }
}

/// What `text` reads as against the sample workspaces in Settings order:
/// Acme, Globex and Personal, then `more` after them.
private func read(_ text: String, more: [(name: String, archived: Bool)] = []) throws -> [String] {
    let desk = try Desk()
    let extra = more.enumerated().map { index, entry in
        let workspace = Workspace(name: entry.name, color: .teal, sortOrder: 3 + index)
        workspace.isArchived = entry.archived
        desk.context.insert(workspace)
        return workspace
    }
    return BarCommand.commands(for: text, in: [desk.acme, desk.globex, desk.personal] + extra).map(phrase)
}

// MARK: - Lengths

@Test(arguments: [
    ("90", 90), ("90m", 90), ("90min", 90), ("90M", 90), ("90MIN", 90),
    ("2h", 120), ("2H", 120), ("1h30", 90), ("1h30m", 90), ("1h30min", 90),
    ("1:30", 90), ("0:30", 30), ("25:00", 1500), ("1", 1),
])
func `a length reads as minutes, hours, both, or hours and minutes with a colon`(text: String, minutes: Int) {
    #expect(BarCommand.minutes(in: text) == minutes)
}

@Test(arguments: [
    "", "0", "00", "0h", "0m", "0:00", "0h0m", "h", "m", "min", "hm",
    "1:5", "1:75", "1:", ":30", "1 30", "90 min", "1h 30m",
    "-5", "1.5h", "90s", "2hm", "abc",
    // Digits from other scripts: Arabic-Indic, fullwidth and Devanagari.
    "٩٠", "９０", "९०",
])
func `text that names no length or a zero length reads as none`(text: String) {
    #expect(BarCommand.minutes(in: text) == nil)
}

@Test(arguments: [
    // Too large for an `Int` to parse at all.
    "99999999999999999999", "99999999999999999999h",
    // Fits as hours, but not once turned into minutes.
    "153722867280912931h",
    // The hours fit as minutes, and the minutes added on top do not.
    "153722867280912930h8",
])
func `a length too large for an Int reads as none and does not crash`(text: String) {
    #expect(BarCommand.minutes(in: text) == nil)
}

@Test(arguments: [
    ("ac 90", "start Acme for 90"), ("ac 90m", "start Acme for 90"), ("ac 90 min", "start Acme for 90"),
    ("ac 2h", "start Acme for 120"), ("AC 2H", "start Acme for 120"), ("ac 1h30", "start Acme for 90"),
    ("ac 1h30m", "start Acme for 90"), ("ac 1h 30m", "start Acme for 90"), ("ac 1:30", "start Acme for 90"),
    ("ac 0:30", "start Acme for 30"),
])
func `every form of a length works after a workspace's name`(text: String, expected: String) throws {
    #expect(try read(text) == [expected])
}

// MARK: - Workspaces

@Test(arguments: [
    ("ac 2h", ["start Acme for 120"]),
    ("pe 25", ["start Personal for 25"]),
    ("gl 45m", ["start Globex for 45"]),
    ("acme 1h", ["start Acme for 60"]),
    ("Acme", ["start Acme"]),
    ("a", ["start Acme"]),
    ("GLOBEX", ["start Globex"]),
    ("  ac   2h  ", ["start Acme for 120"]),
])
func `a workspace matches by the beginning of its name without regard to case`(
    text: String, expected: [String],
) throws {
    #expect(try read(text) == expected)
}

@Test(arguments: ["xyz", "xyz 2h", "acmex", "acme corp", "cme", "acme 1 30", "ac 2x"])
func `a name no workspace begins with gives nothing`(text: String) throws {
    #expect(try read(text).isEmpty)
}

@Test func `an archived workspace never matches, even by its full name`() throws {
    let archived = [(name: "Acme 2", archived: true)]
    #expect(try read("acme 2", more: archived) == ["start Acme for 2"])
    #expect(try read("ac", more: archived) == ["start Acme"])
}

@Test func `an archived sample workspace is not offered`() throws {
    let desk = try Desk()
    desk.globex.isArchived = true
    let workspaces = [desk.acme, desk.globex, desk.personal]

    #expect(BarCommand.commands(for: "gl", in: workspaces).isEmpty)
    #expect(BarCommand.commands(for: "globex 2h", in: workspaces).isEmpty)
    #expect(BarCommand.commands(for: "ac", in: workspaces).map(phrase) == ["start Acme"])
}

@Test func `two workspaces that match both give a result, in Settings order`() throws {
    #expect(try read("ac", more: [("Acme 2", false)]) == ["start Acme", "start Acme 2"])
    #expect(try read("ac 2h", more: [("Acme 2", false)]) == ["start Acme for 120", "start Acme 2 for 120"])

    let desk = try Desk()
    let copy = Workspace(name: "Acme 2", color: .teal, sortOrder: 0)
    desk.context.insert(copy)
    #expect(BarCommand.commands(for: "ac", in: [copy, desk.acme]).map(phrase) == ["start Acme 2", "start Acme"])
}

@Test func `with no workspaces only the timer's commands are offered`() {
    #expect(BarCommand.commands(for: "ac 2h", in: []).isEmpty)
    #expect(BarCommand.commands(for: "p", in: []).map(phrase) == ["pause"])
}

// MARK: - The timer's commands

@Test(arguments: [
    ("p", ["pause", "start Personal"]),
    ("pa", ["pause"]),
    ("pause", ["pause"]),
    ("PAUSE", ["pause"]),
    ("pe", ["start Personal"]),
    ("r", ["resume"]),
    ("resume", ["resume"]),
    ("e", ["end"]),
    ("End", ["end"]),
    ("b", ["break"]),
    ("break", ["break"]),
    ("break 10", ["break 10"]),
    ("B 10", ["break 10"]),
    ("br 1h", ["break 60"]),
    ("break 1:30", ["break 90"]),
    ("break 1h 30m", ["break 90"]),
    ("+", ["+15"]),
    ("+15", ["+15"]),
    ("+ 15", ["+15"]),
    ("+15m", ["+15"]),
])
func `a command matches by the beginning of its word, ahead of any workspace`(
    text: String, expected: [String],
) throws {
    #expect(try read(text) == expected)
}

@Test(arguments: [
    "paused", "ends", "end 5", "pause 5", "resume 5", "breaks", "break 0", "break x", "break 1 30",
    "+30", "+0", "+x", "++15", "x",
])
func `a command with the wrong word or a length it does not take gives nothing`(text: String) throws {
    #expect(try read(text).isEmpty)
}

@Test(arguments: ["", " ", "   ", "\t", "\n", " \t "])
func `an empty field, or one of spaces only, gives nothing`(text: String) throws {
    #expect(try read(text).isEmpty)
}
