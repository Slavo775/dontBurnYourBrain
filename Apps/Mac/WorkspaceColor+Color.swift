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
    /// The face of a key shown beside a row, such as a number key.
    static let keyBackground = Color(nsColor: NSColor(light: 0xF3F5F4, dark: 0x242E2B))
    /// Dividers and outlines.
    static let line = Color(nsColor: NSColor(light: 0xD3DAD7, dark: 0x2B3632))
    /// The gaps that mark the breaks in the progress strip: the surface in
    /// light, as the prototype draws them. In dark that hides them on the empty
    /// part of the strip, so there they take the line's lighter value.
    static let breakGap = Color(nsColor: NSColor(light: 0xFFFFFF, dark: 0x2B3632))
    /// Text.
    static let ink = Color(nsColor: NSColor(light: 0x16201D, dark: 0xE6ECE9))
    /// Secondary text.
    static let muted = Color(nsColor: NSColor(light: 0x5A6964, dark: 0x96A59F))
    /// A working session. The token `ok`.
    static let good = Color(nsColor: NSColor(light: 0x1F7A3D, dark: 0x6BCF8A))
    /// A session that needs you.
    static let warn = Color(nsColor: NSColor(light: 0x9A5B00, dark: 0xE2B25A))
    /// Errors.
    static let bad = Color(nsColor: NSColor(light: 0xA8322A, dark: 0xEE8C83))
    /// The hairline around a floating panel, from the prototype's `--m-shadow`.
    static let ring = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor(hex: 0x16201D).withAlphaComponent(0.07)
    })
}
