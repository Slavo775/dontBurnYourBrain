@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// 2026-01-15 09:00:00 UTC. Every timer test date is built from this, never the clock.
let nine = Date(timeIntervalSince1970: 1_768_467_600)

/// The instant `minutes` after nine.
func at(_ minutes: Double) -> Date {
    nine.addingTimeInterval(minutes * 60)
}

/// An in-memory store with the three sample workspaces and an engine on it.
///
/// Acme keeps the default block length of 60 minutes, Globex has 45 and Personal 25.
struct Desk {
    let container: ModelContainer
    let context: ModelContext
    let engine: TimerEngine
    let acme = Workspace(name: "Acme", color: .teal)
    let globex = Workspace(name: "Globex", color: .indigo, sortOrder: 1)
    let personal = Workspace(name: "Personal", color: .ochre, sortOrder: 2)

    init() throws {
        container = try ModelStore.inMemory()
        context = ModelContext(container)
        globex.defaultBlockMinutes = 45
        personal.defaultBlockMinutes = 25
        context.insert(acme)
        context.insert(globex)
        context.insert(personal)
        try context.save()
        engine = TimerEngine(context: context)
    }

    /// A new context and engine on the same store, as after the app was quit and started again.
    func restarted() -> (engine: TimerEngine, context: ModelContext) {
        let context = ModelContext(container)
        return (TimerEngine(context: context), context)
    }
}

/// Every entry in the store, earliest first.
func entries(_ context: ModelContext) throws -> [TimeEntry] {
    try context.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.start)]))
}

/// Every block in the store, earliest first.
func blocks(_ context: ModelContext) throws -> [TimeBlock] {
    try context.fetch(FetchDescriptor<TimeBlock>(sortBy: [SortDescriptor(\.plannedStart)]))
}

/// Checks the rules every history keeps: at most one running entry and one
/// running block, no end before its start, no overlap, and every break inside
/// a block, within the block's span.
func expectHistoryKeepsRules(_ context: ModelContext, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let all = try entries(context)
    let open = all.filter { $0.end == nil }
    #expect(open.count <= 1, "more than one running entry", sourceLocation: sourceLocation)
    #expect(try blocks(context).count { $0.state == .running } <= 1, sourceLocation: sourceLocation)
    for entry in open {
        #expect(entry.block?.state == .running, "a running entry outside a block", sourceLocation: sourceLocation)
    }
    for entry in all {
        #expect((entry.end ?? entry.start) >= entry.start, "an end before its start", sourceLocation: sourceLocation)
        if entry.kind == .break {
            #expect(entry.block != nil, "a break outside a block", sourceLocation: sourceLocation)
        }
        if let block = entry.block {
            #expect(entry.start >= block.plannedStart, "an entry before its block", sourceLocation: sourceLocation)
            #expect(entry.workspace === block.workspace, sourceLocation: sourceLocation)
        }
    }
    for (earlier, later) in zip(all, all.dropFirst()) {
        #expect((earlier.end ?? .distantFuture) <= later.start, "entries overlap", sourceLocation: sourceLocation)
    }
}
