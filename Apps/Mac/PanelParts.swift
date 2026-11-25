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
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
                .frame(width: 30, height: 30)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(navigation.isExpanded ? "Collapse the panel" : "Expand the panel")
    }
}

struct PanelBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Back")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.sunken, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
