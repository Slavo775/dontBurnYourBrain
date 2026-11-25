import AppKit
import DontBurnCore
import SwiftUI

/// The right-click menu: the timer's actions while a block or a break runs,
/// or "Take a break" while nothing runs, then the first three workspaces to
/// start, then the window, Settings and Quit.
struct StatusItemMenu: View {
    let countdown: Countdown
    let openWindow: () -> Void

    var body: some View {
        let state = countdown.state
        if state != .idle {
            if QuickAction.pauseOrResume.isAvailable(in: state) {
                Button(state == .paused ? "Resume" : "Pause") {
                    countdown.perform(.pauseOrResume)
                }
            }
            if state.isBreak {
                Button("End break") {
                    countdown.perform(.breakOrEndBreak)
                }
            } else {
                BreakLengthMenu(countdown: countdown)
                    .disabled(!QuickAction.canStartBreak(in: state))
            }
            Button("Add 15 minutes") {
                countdown.perform(.extend)
            }
            if state.hasBlock {
                Button("End block") {
                    countdown.endBlock()
                }
            }
            Divider()
        } else if countdown.hasStore {
            BreakLengthMenu(countdown: countdown)
            Divider()
        }
        let starts = countdown.workspaces.prefix(WorkspaceRoster.menuStartCount)
        if !starts.isEmpty {
            // While a block runs, a start acts as a switch.
            ForEach(starts) { workspace in
                Button("Start \(workspace.name) for \(blockLength(workspace.defaultBlockMinutes))") {
                    countdown.start(workspace)
                }
            }
            Divider()
        }
        Button("Open the window", action: openWindow)
            .keyboardShortcut("o")
        OpenSettingsButton()
        Divider()
        Button("Quit \(Bundle.main.displayName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// "Take a break", a submenu with the break's lengths.
private struct BreakLengthMenu: View {
    let countdown: Countdown

    var body: some View {
        Menu("Take a break") {
            ForEach(TimerEngine.breakLengthChoices, id: \.self) { minutes in
                Button("\(minutes) min") {
                    countdown.startBreak(minutes: minutes)
                }
            }
        }
    }
}
