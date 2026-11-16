import Foundation

/// A fixed instant for the clock, so a screenshot is the same on every run.
///
/// The value comes from a launch argument, which is input from outside the
/// app, so its size and shape are checked before it is read.
public enum FixedTime {
    /// The longest value that is parsed at all. A valid one has 25 characters.
    static let maximumLength = 32

    /// The instant an ISO 8601 date and time names, such as
    /// `2026-01-15T09:41:30+01:00` or `2026-01-15T09:41:30Z`.
    ///
    /// Seconds and an offset, `Z` or `±hh:mm`, are required, and fractions of
    /// a second are not accepted. Returns `nil` when the value is empty, too
    /// long, in another shape, or names a time that does not exist, such as
    /// February 30 or 25:00.
    public static func date(from raw: String) -> Date? {
        // ASCII only, or `\d` would also take digits from other scripts.
        let shape = /(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:Z|([+-])(\d\d):(\d\d))/.asciiOnlyDigits()
        guard raw.utf8.count <= maximumLength, let match = raw.wholeMatch(of: shape) else { return nil }
        let (_, year, month, day, hour, minute, second, sign, offsetHours, offsetMinutes) = match.output
        let offset = (Int(offsetHours ?? "0") ?? 0) * 3600 + (Int(offsetMinutes ?? "0") ?? 0) * 60
        guard let zone = TimeZone(secondsFromGMT: sign == "-" ? -offset : offset) else { return nil }
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: zone,
            year: Int(year),
            month: Int(month),
            day: Int(day),
            hour: Int(hour),
            minute: Int(minute),
            second: Int(second),
        )
        return components.isValidDate ? components.date : nil
    }
}

/// The light or dark appearance one launch of the app is set to.
///
/// The raw values are the values the launch argument takes, so
/// `Appearance(rawValue:)` reads it: any other value is `nil`, and the app
/// then follows the system.
public enum Appearance: String, Sendable {
    /// The light appearance.
    case light
    /// The dark appearance.
    case dark
}
