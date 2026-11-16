@testable import DontBurnCore
import Foundation
import Testing

/// 2026-01-15 08:41:30 UTC, the instant the screenshot argument names.
private let screenshotInstant = Date(timeIntervalSince1970: 1_768_466_490)

@Test(arguments: [
    "2026-01-15T09:41:30+01:00",
    "2026-01-15T08:41:30Z",
    "2026-01-15T03:11:30-05:30",
    "2026-01-15T22:41:30+14:00",
    "2026-01-14T14:41:30-18:00",
    "2026-01-15T08:41:30-00:00",
])
func `fixed time names the same instant whatever offset it is written with`(raw: String) {
    #expect(FixedTime.date(from: raw) == screenshotInstant)
}

@Test func `fixed time accepts February 29 in a leap year`() {
    #expect(FixedTime.date(from: "2028-02-29T12:00:00Z") == Date(timeIntervalSince1970: 1_835_438_400))
}

@Test(arguments: [
    "2026-02-29T12:00:00Z",
    "2026-02-30T12:00:00Z",
    "2026-04-31T12:00:00Z",
    "2026-00-15T12:00:00Z",
    "2026-13-15T12:00:00Z",
    "2026-01-00T12:00:00Z",
    "2026-01-15T24:00:00Z",
    "2026-01-15T25:00:00Z",
    "2026-01-15T09:60:00Z",
    "2026-01-15T09:41:60Z",
    "0000-01-15T09:41:30Z",
])
func `fixed time rejects a date or time that does not exist`(raw: String) {
    #expect(FixedTime.date(from: raw) == nil)
}

@Test(arguments: ["+18:01", "-18:01", "+19:00", "+25:00", "-99:00"])
func `fixed time rejects an offset beyond eighteen hours`(offset: String) {
    #expect(FixedTime.date(from: "2026-01-15T09:41:30\(offset)") == nil)
}

@Test(arguments: [
    "",
    "garbage",
    "2026-01-15T09:41:30",
    "2026-01-15 09:41:30Z",
    "2026-01-15t09:41:30Z",
    "2026-01-15T09:41:30z",
    "2026-01-15T09:41:30.5Z",
    "2026-01-15T09:41Z",
    "2026-1-15T09:41:30Z",
    "2026-01-15T09:41:30+0100",
    "2026-01-15T09:41:30+01",
    "2026-01-15T09:41:30\u{2212}05:30",
    " 2026-01-15T09:41:30Z",
    "2026-01-15T09:41:30Z ",
    "2026-01-15T09:41:30Z\n",
    "2026-01-15T09:41:30Zjunk",
    "x2026-01-15T09:41:30Z",
    "+2026-01-15T09:41:30Z",
    "12026-01-15T09:41:30Z",
])
func `fixed time rejects any other shape`(raw: String) {
    #expect(FixedTime.date(from: raw) == nil)
}

@Test(arguments: [
    // Arabic-Indic digits.
    "\u{662}\u{660}\u{662}\u{666}-01-15T09:41:30Z",
    // Fullwidth digits.
    "2026-01-15T\u{FF10}\u{FF19}:41:30Z",
    // Devanagari digits in the offset.
    "2026-01-15T09:41:30+\u{966}\u{967}:00",
])
func `fixed time accepts only ASCII digits`(raw: String) {
    #expect(FixedTime.date(from: raw) == nil)
}

@Test func `the length limit leaves room for the longest valid value`() {
    #expect("2026-01-15T09:41:30+01:00".utf8.count <= FixedTime.maximumLength)
}

@Test func `fixed time rejects a value longer than the limit without reading it`() {
    let padded = "2026-01-15T09:41:30Z" + String(repeating: " ", count: FixedTime.maximumLength)
    let huge = String(repeating: "2026-01-15T09:41:30Z", count: 100_000)

    #expect(FixedTime.date(from: padded) == nil)
    #expect(FixedTime.date(from: huge) == nil)
}

@Test(arguments: [("light", Appearance.light), ("dark", Appearance.dark)])
func `appearance reads light and dark`(raw: String, appearance: Appearance) {
    #expect(Appearance(rawValue: raw) == appearance)
}

@Test(arguments: ["", "purple", "Light", "DARK", " dark", "dark ", "auto", "system"])
func `appearance ignores any other value, so the app follows the system`(raw: String) {
    #expect(Appearance(rawValue: raw) == nil)
}
