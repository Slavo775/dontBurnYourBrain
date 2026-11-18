import AppKit
import DontBurnCore
import SwiftUI

extension WorkspaceColor {
    /// The palette color, with its light and dark value from `docs/spec/design.md`.
    var color: Color {
        let (light, dark) = hexValues
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    /// The color's name, for VoiceOver.
    var name: LocalizedStringKey {
        switch self {
        case .teal: "Teal"
        case .orange: "Orange"
        case .indigo: "Indigo"
        case .raspberry: "Raspberry"
        case .ochre: "Ochre"
        case .slate: "Slate"
        }
    }

    private var hexValues: (light: Int, dark: Int) {
        switch self {
        case .teal: (0x0B6E5C, 0x4FC3A8)
        case .orange: (0xC2571A, 0xE88B55)
        case .indigo: (0x4F5BB5, 0x8E99EA)
        case .raspberry: (0xA8386A, 0xF08FB5)
        case .ochre: (0x86690A, 0xDCC056)
        case .slate: (0x566670, 0xA9B7C0)
        }
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1,
        )
    }
}
