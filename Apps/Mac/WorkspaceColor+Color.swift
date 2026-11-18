import AppKit
import DontBurnCore
import SwiftUI

extension WorkspaceColor {
    /// The palette color, with its light and dark value from `docs/spec/design.md`.
    var color: Color {
        Color(nsColor: nsColor)
    }

    /// The palette color for AppKit drawing, resolved for the appearance it is drawn in.
    var nsColor: NSColor {
        let (light, dark) = hexValues
        return NSColor(light: light, dark: dark)
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

extension NSColor {
    /// A color with a light and a dark hex value, resolved for the appearance it is drawn in.
    convenience init(light: Int, dark: Int) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    /// An sRGB color from a hex value such as `0x0B6E5C`.
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1,
        )
    }
}

extension Color {
    /// Panels and windows. The tokens are in "Colors and type", `docs/spec/design.md`.
    static let surface = Color(nsColor: NSColor(light: 0xFFFFFF, dark: 0x18201D))
    /// Buttons, rows, the empty part of the progress strip.
    static let sunken = Color(nsColor: NSColor(light: 0xE9EDEB, dark: 0x0C110F))
    /// Dividers and outlines.
    static let line = Color(nsColor: NSColor(light: 0xD3DAD7, dark: 0x2B3632))
    /// Text.
    static let ink = Color(nsColor: NSColor(light: 0x16201D, dark: 0xE6ECE9))
    /// Secondary text.
    static let muted = Color(nsColor: NSColor(light: 0x5A6964, dark: 0x96A59F))
}
