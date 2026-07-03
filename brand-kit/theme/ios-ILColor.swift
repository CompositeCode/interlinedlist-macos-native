//  InterlinedList — Strata · iOS / macOS color tokens
//  Colors adapt automatically to light / dark via UITraitCollection.
//  For SwiftUI. Fonts: register Space Grotesk, Manrope, JetBrains Mono.

import SwiftUI

public enum ILColor {
    // MARK: Brand (constant)
    public static let green      = Color(hex: 0x2FA877)   // primary action
    public static let greenHover = Color(hex: 0x28936A)
    public static let greenDark  = Color(hex: 0x3FBF8C)   // primary in dark
    public static let teal       = Color(hex: 0x184860)   // structure / masthead
    public static let tealDeep   = Color(hex: 0x0C2C3A)   // dark masthead
    public static let tealAccent = Color(hex: 0x7FB8C4)   // links in dark
    public static let tealBright = Color(hex: 0x4FD09C)   // wordmark accent
    public static let amber      = Color(hex: 0xF0A830)   // live / Dig

    // MARK: Theme-adaptive (light / dark)
    public static let background = dynamic(light: 0xF4EEE2, dark: 0x121317)
    public static let surface    = dynamic(light: 0xFBF7EF, dark: 0x17191F)
    public static let surface2   = dynamic(light: 0xF6F1E7, dark: 0x1B1D23)
    public static let text       = dynamic(light: 0x16323C, dark: 0xF3F1EA)
    public static let textBody   = dynamic(light: 0x22383E, dark: 0xE4E1D9)
    public static let masthead   = dynamic(light: 0x184860, dark: 0x0C2C3A)
    public static let primary    = dynamic(light: 0x2FA877, dark: 0x3FBF8C)
    public static let link       = dynamic(light: 0x184860, dark: 0x7FB8C4)

    private static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

public enum ILType {
    public static let display = "SpaceGrotesk-Bold"
    public static let title   = "SpaceGrotesk-Bold"
    public static let body    = "Manrope-Regular"
    public static let mono    = "JetBrainsMono-Medium"
}

public enum ILMetric {
    public static let radiusSm: CGFloat = 3, radiusMd: CGFloat = 4, radiusLg: CGFloat = 10
    public static let space: [CGFloat] = [4, 8, 12, 16, 20, 24, 32, 40, 48]
}

// Helpers
extension Color { init(hex: UInt) {
    self.init(.sRGB, red: Double((hex >> 16) & 0xFF)/255,
                     green: Double((hex >> 8) & 0xFF)/255,
                     blue: Double(hex & 0xFF)/255) } }
extension UIColor { convenience init(rgb: UInt) {
    self.init(red: CGFloat((rgb >> 16) & 0xFF)/255,
              green: CGFloat((rgb >> 8) & 0xFF)/255,
              blue: CGFloat(rgb & 0xFF)/255, alpha: 1) } }
