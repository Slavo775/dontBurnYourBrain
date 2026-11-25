import DontBurnCore
import SwiftUI

extension View {
    /// The panel's text, and its background with its corners and hairline.
    func panelSurface() -> some View {
        font(.system(size: 13))
            .foregroundStyle(Color.ink)
            .background(Color.surface, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ring)
            }
    }
}

/// A panel title on the left, and an optional control on the right.
struct PanelTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing
        }
        .frame(minHeight: 36)
    }
}

/// Widens the panel, or collapses the wide one. ⌘E does the same.
struct ExpandButton: View {
    let navigation: PanelNavigation

    var body: some View {
        Button {
            navigation.isExpanded.toggle()
        } label: {
            Image(systemName: navigation.isExpanded
                ? "arrow.up.right.and.arrow.down.left"
                : "arrow.down.left.and.arrow.up.right")
        }
        .buttonStyle(PanelIconButtonStyle())
        .accessibilityLabel(navigation.isExpanded ? "Collapse the panel" : "Expand the panel")
    }
}

/// The prototype's `m-icon`, with its hover look while pressed, as the four
/// quick actions have theirs.
private struct PanelIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(configuration.isPressed ? Color.ink : Color.muted)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? Color.sunken : Color.clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
    }
}

struct PanelBackButton: View {
    let action: () -> Void

    var body: some View {
        Button("Back", action: action)
            .buttonStyle(PanelButtonStyle())
    }
}

/// The prototype's small button (`m-btn`).
struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.line : Color.sunken, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
    }
}

struct WorkspaceDot: View {
    let color: WorkspaceColor

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: 10, height: 10)
    }
}
