import Foundation

/// Something typed into the command bar, before the timer's state decides
/// what it does. See ``result(in:dueBreakMinutes:lastBreakMinutes:)``.
public enum BarCommand: Equatable {
    /// Start a block for the workspace, of `minutes`, or of its default length
    /// when `nil`, with its default rhythm. While a block runs it switches.
    case start(Workspace, minutes: Int?)
    /// Pause, or Resume while paused, as P in the panel.
    case pause
    /// Resume the paused block.
    case resume
    /// A break of `minutes`. When `nil`, as Return in "Break for": the planned
    /// break that is due, otherwise one of the last length used, and on a
    /// break it ends the break.
    case takeBreak(minutes: Int?)
    /// Add ``TimerEngine/defaultExtendMinutes``, as +15 in the panel.
    case extend
    /// End the running block.
    case end

    /// The words that name a command, each matched by its beginning.
    private static var words: [(word: String, command: Self)] {
        [("pause", .pause), ("resume", .resume), ("break", .takeBreak(minutes: nil)), ("end", .end)]
    }

    /// What `text` asks for, the timer's commands first, then one start per
    /// matching workspace among `workspaces`, in their order. Empty for an
    /// empty text and when nothing matches.
    ///
    /// A command word matches by its beginning, without regard to case, so
    /// `p` already offers Pause. `break` takes a length after it, as in
    /// `break 10`, and `+15` adds 15 minutes. A workspace matches when its
    /// name begins with what was typed before the length, without regard to
    /// case, as `ac 2h` for Acme. An archived workspace never matches. A
    /// length is read by ``minutes(in:)``.
    public static func commands(for text: String, in workspaces: [Workspace]) -> [Self] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return [] }
        return timerCommands(first: first, rest: Array(words.dropFirst())) + starts(words, in: workspaces)
    }

    /// `pause`, `resume`, `break`, `break 10`, `end` and `+15`, from the first
    /// typed word and the words after it.
    private static func timerCommands(first: String, rest: [String]) -> [Self] {
        if first.hasPrefix("+") {
            let amount = String(first.dropFirst()) + rest.joined()
            // A bare `+` already offers it, as a letter offers its word.
            return amount.isEmpty || minutes(in: amount) == TimerEngine.defaultExtendMinutes ? [.extend] : []
        }
        if rest.isEmpty {
            return words.filter { $0.word.hasPrefix(first) }.map(\.command)
        }
        if "break".hasPrefix(first), let minutes = length(of: rest) {
            return [.takeBreak(minutes: minutes)]
        }
        return []
    }

    /// One start per active workspace whose name begins with the typed name.
    ///
    /// The length is the last word, or the last two as in `1h 30m`, and the
    /// words before it name the workspace. Without a length the whole text
    /// names it. Each workspace takes the first reading that matches it, the
    /// one with the longest name first. The workspaces the whole text names
    /// come first, then the others, each in Settings order, so `acme 2`
    /// offers "Acme 2" at its default length before Acme for 2 minutes.
    private static func starts(_ words: [String], in workspaces: [Workspace]) -> [Self] {
        let readings: [(name: String, minutes: Int?)] = (0 ... min(2, words.count - 1)).compactMap { count in
            guard count > 0 else { return (words.joined(separator: " "), nil) }
            return length(of: Array(words.suffix(count))).map { (words.dropLast(count).joined(separator: " "), $0) }
        }
        let matches = workspaces.filter { !$0.isArchived }.compactMap { workspace -> (reading: Int, start: Self)? in
            let name = workspace.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return readings.firstIndex { name.range(of: $0.name, options: [.anchored, .caseInsensitive]) != nil }
                .map { ($0, .start(workspace, minutes: readings[$0].minutes)) }
        }
        // The first reading is the whole text.
        return matches.filter { $0.reading == 0 }.map(\.start) + matches.filter { $0.reading != 0 }.map(\.start)
    }

    /// The minutes in one or two typed words, or `nil`.
    ///
    /// Two words are one length only as hours then minutes (`1h 30m`, `1h 30`)
    /// or as a number then its unit (`90 min`). So `2 1h` and `1 30` are not
    /// one length, and a name that ends in a number, such as "Acme 2", keeps it.
    private static func length(of words: [String]) -> Int? {
        let hours = /\d+h/.asciiOnlyDigits(), minutes = /\d+(?:m|min)?/.asciiOnlyDigits()
        switch words.count {
        case 1:
            return Self.minutes(in: words[0])
        case 2 where words[0].wholeMatch(of: hours) != nil && words[1].wholeMatch(of: minutes) != nil,
             2 where Int(words[0]) != nil && ["m", "min"].contains(words[1]):
            return Self.minutes(in: words.joined())
        default:
            return nil
        }
    }

    /// The minutes a typed length names, or `nil` when it names none or zero.
    ///
    /// The forms are minutes (`90`, `90m`, `90min`), hours (`2h`), both
    /// (`1h30`, `1h30m`) and hours and minutes with a colon (`1:30`), without
    /// regard to case. A length that does not fit in an `Int` names none.
    public static func minutes(in text: String) -> Int? {
        // ASCII only, or `\d` would also take digits from other scripts.
        let clock = /(\d+):([0-5]\d)/.asciiOnlyDigits()
        let units = /(?:(\d+)h)?(?:(\d+)(?:m|min)?)?/.asciiOnlyDigits()
        let text = text.lowercased()
        let parts: (hours: Substring?, minutes: Substring?)
        if let match = text.wholeMatch(of: clock) {
            parts = (match.output.1, match.output.2)
        } else if let match = text.wholeMatch(of: units) {
            parts = (match.output.1, match.output.2)
        } else {
            return nil
        }
        guard parts.hours != nil || parts.minutes != nil,
              let hours = Int(parts.hours ?? "0"), let minutes = Int(parts.minutes ?? "0")
        else { return nil }
        let (inHours, overflow) = hours.multipliedReportingOverflow(by: 60)
        let (total, sumOverflow) = inHours.addingReportingOverflow(minutes)
        guard !overflow, !sumOverflow, total > 0 else { return nil }
        return total
    }

    /// What this command does in `state`, or why it cannot.
    ///
    /// `dueBreakMinutes` is the planned break that is due while working, see
    /// ``CompactPanel/dueBreakMinutes``, and `lastBreakMinutes` the last
    /// break length used. The rules are the panel's: a break cannot start
    /// while paused or on a break, a break with nothing running is at most
    /// ``IdleBreak/maximumLength``, and on a break with no block there is
    /// nothing to pause or end. A typed length for a block is at most
    /// ``IdleBreak/maximumLength`` too.
    public func result(in state: TimerState, dueBreakMinutes: Int?, lastBreakMinutes: Int) -> BarResult {
        switch self {
        case let .start(workspace, minutes):
            BarResult(
                .start(workspace, minutes: minutes ?? workspace.defaultBlockMinutes),
                // The same day a break with nothing running may last, for a typed length only.
                refusal: minutes.map { TimeInterval($0) * 60 > IdleBreak.maximumLength } == true ? .blockTooLong : nil,
            )
        case .pause: Self.pause(in: state)
        case .resume: Self.resume(in: state)
        case let .takeBreak(minutes?): Self.startBreak(minutes: minutes, in: state)
        case .takeBreak(nil): Self.takeBreak(in: state, due: dueBreakMinutes, last: lastBreakMinutes)
        case .extend: BarResult(.extend, refusal: state == .idle ? .nothingRunning : nil)
        case .end: Self.end(in: state)
        }
    }

    private static func pause(in state: TimerState) -> BarResult {
        switch state {
        case .paused: BarResult(.resume)
        case .working, .onBreak: BarResult(.pause)
        case .idle: BarResult(.pause, refusal: .nothingRunning)
        case .idleBreak: BarResult(.pause, refusal: .noBlock)
        }
    }

    private static func resume(in state: TimerState) -> BarResult {
        switch state {
        case .paused: BarResult(.resume)
        case .idle: BarResult(.resume, refusal: .nothingRunning)
        default: BarResult(.resume, refusal: .notPaused)
        }
    }

    private static func end(in state: TimerState) -> BarResult {
        switch state {
        case .idle: BarResult(.endBlock, refusal: .nothingRunning)
        case .idleBreak: BarResult(.endBlock, refusal: .noBlock)
        default: BarResult(.endBlock)
        }
    }

    private static func takeBreak(in state: TimerState, due: Int?, last: Int) -> BarResult {
        if state.isBreak {
            return BarResult(.endBreak)
        }
        if state == .working, let due {
            return BarResult(.plannedBreak(minutes: due))
        }
        return startBreak(minutes: last, in: state)
    }

    private static func startBreak(minutes: Int, in state: TimerState) -> BarResult {
        let refusal: BarRefusal? = switch state {
        case .paused: .paused
        case .onBreak, .idleBreak: .onBreak
        case .idle where TimeInterval(minutes) * 60 > IdleBreak.maximumLength: .tooLong
        default: nil
        }
        return BarResult(.startBreak(minutes: minutes), refusal: refusal)
    }
}

/// What a command in the command bar does, with its lengths filled in.
public enum BarAction: Equatable {
    /// Start a block for the workspace, of `minutes`, or switch to it.
    case start(Workspace, minutes: Int)
    /// Pause the block, which on a break ends the break.
    case pause
    /// Resume the paused block.
    case resume
    /// Start a break of `minutes`, inside the block or with nothing running.
    case startBreak(minutes: Int)
    /// Start the planned break that is due, of `minutes`.
    case plannedBreak(minutes: Int)
    /// End the break, with or without a block.
    case endBreak
    /// Add ``TimerEngine/defaultExtendMinutes`` to the block or the break.
    case extend
    /// End the running block.
    case endBlock
}

/// Why the command bar cannot take an action in the timer's state now.
public enum BarRefusal: Equatable, Sendable {
    /// Nothing runs, so there is nothing to pause, resume, extend or end.
    case nothingRunning
    /// The block is paused, so a break cannot start: resume first.
    case paused
    /// Resume while the block is not paused.
    case notPaused
    /// A break already runs.
    case onBreak
    /// A break with no block runs, so there is no block to pause or end.
    case noBlock
    /// A break with nothing running would be longer than ``IdleBreak/maximumLength``.
    case tooLong
    /// A block of the typed length would be longer than ``IdleBreak/maximumLength``, a day.
    case blockTooLong
}

/// One row of the command bar: an action and, when it cannot be taken, why.
public struct BarResult: Equatable {
    /// What the row does.
    public let action: BarAction
    /// Why it cannot be taken now, or `nil` when it can.
    public let refusal: BarRefusal?

    /// A row for `action`, refused for `refusal` when one is given.
    public init(_ action: BarAction, refusal: BarRefusal? = nil) {
        self.action = action
        self.refusal = refusal
    }
}
