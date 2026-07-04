//  InterlinedList — Strata typography tokens
//  Space Grotesk and Manrope are variable fonts; JetBrains Mono uses static files.
//  All must be listed in Info.plist under UIAppFonts.
//  Source of truth: brand-kit/theme/tokens.json

import SwiftUI

extension Font {
    static func ilDisplay(_ size: CGFloat = 28) -> Font {
        Font.custom("Space Grotesk", size: size).weight(.bold)
    }

    static func ilTitle(_ size: CGFloat = 17) -> Font {
        Font.custom("Space Grotesk", size: size).weight(.bold)
    }

    static func ilSubtitle(_ size: CGFloat = 15) -> Font {
        Font.custom("Space Grotesk", size: size).weight(.medium)
    }

    static func ilBody(_ size: CGFloat = 13) -> Font {
        Font.custom("Manrope", size: size)
    }

    static func ilBodyMedium(_ size: CGFloat = 13) -> Font {
        Font.custom("Manrope", size: size).weight(.medium)
    }

    static func ilMono(_ size: CGFloat = 12) -> Font {
        Font.custom("JetBrainsMono-Medium", size: size)
    }
}
