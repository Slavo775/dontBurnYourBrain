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
        let shape = /(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:Z|([+-])(\d\d):([0-5]\d))/.asciiOnlyDigits()
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

/// The stand-in for the home folder that the Dev build looks for Claude Code
/// profiles in, so it never looks at the real one.
///
/// The value comes from a launch argument, which is input from outside the
/// app, so its size and shape are checked before it is used.
public enum ProfileStandIn {
    /// The longest value that is used at all, `PATH_MAX`.
    static let maximumLength = 1024

    /// The folder `raw` names, with its symlinks resolved, or `nil` when it is
    /// empty, too long, not absolute, holds a control character, or is the
    /// real `home`, lies inside it or holds it.
    ///
    /// A path inside `home` is refused before it is resolved, so no real
    /// profile folder is looked at.
    public static func folder(from raw: String, home: String) -> String? {
        guard raw.utf8.count <= maximumLength, raw.hasPrefix("/"),
              !raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else { return nil }
        let spelled = FolderPath.standardized(raw)
        let homes = [FolderPath.standardized(home), FolderPath.resolved(home)]
        guard !homes.contains(where: { FolderPath.path(spelled, isInside: $0) }) else { return nil }
        let folder = FolderPath.resolved(spelled)
        let overlaps = homes.contains { FolderPath.path(folder, isInside: $0) || FolderPath.path($0, isInside: folder) }
        return overlaps ? nil : folder
    }
}

/// The Dev build's stand-ins for time away from the Mac, so a check needs no
/// real absence: a short threshold, and an idle time that runs in cycles.
///
/// The values come from launch arguments, which are input from outside the
/// app, so their size and shape are checked before they are read.
public enum AwayStandIn {
    /// The longest idle cycle, in seconds: a day.
    static let maximumCycle = 24 * 60 * 60

    /// The threshold `raw` names, in minutes, or `nil` unless it is ASCII
    /// digits alone, within ``TimeAway/thresholdRange``.
    public static func thresholdMinutes(from raw: String) -> Int? {
        wholeNumber(from: raw, in: TimeAway.thresholdRange)
    }

    /// The length of one idle cycle `raw` names, in seconds, or `nil` unless
    /// it is ASCII digits alone, from 1 to a day.
    public static func idleCycle(from raw: String) -> Int? {
        wholeNumber(from: raw, in: 1 ... maximumCycle)
    }

    /// The seconds since the last input at `now`, when input comes once every
    /// `cycle` seconds from `launch` on: each cycle is a time away, and its
    /// end a return. Zero before `launch`.
    public static func secondsSinceLastInput(at now: Date, launch: Date, cycle: Int) -> TimeInterval {
        max(0, now.timeIntervalSince(launch)).truncatingRemainder(dividingBy: TimeInterval(max(1, cycle)))
    }

    private static func wholeNumber(from raw: String, in range: ClosedRange<Int>) -> Int? {
        // At most six digits, so nothing longer is read at all.
        guard (1 ... 6).contains(raw.utf8.count), raw.utf8.allSatisfy({ (0x30 ... 0x39).contains($0) }),
              let value = Int(raw), range.contains(value)
        else { return nil }
        return value
    }
}

/// Where one build looks for Claude Code profiles, and the folder it may read
/// and write settings files in.
public struct ProfileReach: Equatable, Sendable {
    /// The folder whose top level holds the profiles, or `nil` for none.
    public let home: String?
    /// The folder settings files may be read and written in, as
    /// ``HookInstaller/init(command:directory:allowedFolder:)`` takes it, or `nil` for none.
    public let allowedFolder: String?

    /// The reach of the Release build, when `isDev` is false: the real `home`,
    /// and `/`. The reach of the Dev build: the folder `standIn` names, for
    /// both, once ``ProfileStandIn/folder(from:home:)`` accepts it, and
    /// otherwise none. So the Dev build never looks at the real home folder
    /// and never gets `/`.
    public init(isDev: Bool, standIn: String?, home: String) {
        if isDev {
            let folder = standIn.flatMap { ProfileStandIn.folder(from: $0, home: home) }
            self.home = folder
            allowedFolder = folder
        } else {
            self.home = home
            allowedFolder = "/"
        }
    }
}
