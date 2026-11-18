import AppKit
import DontBurnCore
import SwiftData
import SwiftUI

/// The window with Today and History, opened with ⌘O from the panel and from
/// the right-click menu.
///
/// An `NSWindow` held here rather than a SwiftUI scene, so the panel's key
/// handler, which has no SwiftUI environment, can open it too. The app has no
/// Dock icon, so the window opens behind the active app unless the app is
/// activated and the window ordered front by hand.
@MainActor
final class MainWindowController {
    private let container: ModelContainer?
    private let fixedTime: Date?
    private let onChange: () -> Void

    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true,
        )
        window.title = Bundle.main.displayName
        window.isReleasedWhenClosed = false
        // The title bar shows the surface beneath it, as in the prototype.
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentViewController = NSHostingController(
            rootView: MainWindowView(container: container, fixedTime: fixedTime, onChange: onChange),
        )
        window.setContentSize(NSSize(width: 860, height: 560))
        window.contentMinSize = NSSize(width: 680, height: 400)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        return window
    }()

    /// A window over the store in `container`, or saying the data could not be
    /// opened when it is `nil`. `onChange` runs after every saved change, so
    /// the menu bar item and the panel follow at once.
    init(container: ModelContainer?, fixedTime: Date?, onChange: @escaping () -> Void) {
        self.container = container
        self.fixedTime = fixedTime
        self.onChange = onChange
    }

    /// Opens the window, or brings it forward, in front of the active app.
    func show() {
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        // `activate()` is only a request, which another active app may decline.
        window.orderFrontRegardless()
    }
}

/// The sidebar items.
private enum WindowPage: Hashable {
    case today
    case history
}

/// The sidebar with Today and History, and the chosen page.
struct MainWindowView: View {
    let container: ModelContainer?
    let fixedTime: Date?
    let onChange: () -> Void

    @State private var page: WindowPage? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                // The prototype's icons: a clock for Today, bars for History.
                Label("Today", systemImage: "clock").tag(WindowPage.today)
                Label("History", systemImage: "chart.bar").tag(WindowPage.history)
            }
            .navigationSplitViewColumnWidth(210)
            .scrollContentBackground(.hidden)
            .background(Color.sunken)
        } detail: {
            Group {
                if let context = container?.mainContext {
                    switch page {
                    case .history:
                        DayView(context: context, fixedTime: fixedTime, isHistory: true, onChange: onChange)
                    default:
                        DayView(context: context, fixedTime: fixedTime, isHistory: false, onChange: onChange)
                    }
                } else {
                    ContentUnavailableView(
                        "The data could not be opened",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Entries can't be shown or changed right now."),
                    )
                }
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
        }
    }
}

#Preview("Sample data") {
    MainWindowView(container: .sample, fixedTime: Date(timeIntervalSince1970: 1_768_466_490), onChange: {})
        .frame(width: 860, height: 560)
}

#Preview("No store") {
    MainWindowView(container: nil, fixedTime: nil, onChange: {})
        .frame(width: 860, height: 560)
}
