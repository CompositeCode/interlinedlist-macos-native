# InterlinedList — Brand Kit ("Strata")

Everything the web, iOS, macOS, Windows, Linux, and Android teams need to
re-brand InterlinedList on a shared visual system.

> **Direction:** Strata — deep-teal structure, green as the action color,
> amber for live/Dig, on a soft-sand light theme and a near-black dark theme.
> Type: **Space Grotesk** (display) · **Manrope** (body) · **JetBrains Mono** (time/meta).

---

## Contents

```
brand-kit/
├─ README.md                     ← you are here
├─ HANDOFF.md                    ← what to give each team + Claude starter prompts
├─ logo/
│   ├─ logo-icon.svg             ← vector mark (crisp at any size)
│   └─ logo-icon-master.png      ← 321px master raster (transparent)
├─ icons/                        ← export-ready app icons + packaged bundles
│   ├─ ios/        AppIcon-*.png (1024→40) + dark 1024
│   ├─ macos/      icon-*.png (1024→16) + InterlinedList.icns (ready)
│   ├─ android/    ic_launcher-*.png + adaptive fg/bg layers
│   ├─ windows/    icon-*.png (256→16) + InterlinedList.ico (ready)
│   ├─ linux/      icon-*.png (512→48) hicolor set
│   └─ web/        favicon 16/32/48, apple-touch-180, 192, 512, maskable, dark
├─ theme/
│   ├─ tokens.json               ← source of truth for all platforms
│   ├─ interlinedlist-theme.css  ← web: CSS variables + prefers-color-scheme + components
│   ├─ android-colors.xml        ← Android View system (values / values-night)
│   ├─ android-Color.kt          ← Android Jetpack Compose
│   └─ ios-ILColor.swift         ← iOS / macOS SwiftUI
└─ guidelines/
    └─ brand-guidelines.html     ← printable one-doc reference (open in a browser → Print → PDF)
```

## Color roles

| Token   | Hex (light / dark)      | Use |
|---------|--------------------------|-----|
| Green   | `#2FA877` / `#3FBF8C`    | Primary action — Post, Compose, Follow |
| Teal    | `#184860` / `#0C2C3A`    | Structure — masthead, rails, card edges |
| Amber   | `#F0A830`                | Live status, Digs, highlights |
| Base    | `#F4EEE2` / `#121317`    | App background |
| Surface | `#FBF7EF` / `#17191F`    | Cards, panels |
| Text    | `#16323C` / `#F3F1EA`    | Primary text |

## Per-team quick start

- **Web** — link `theme/interlinedlist-theme.css`; it exposes `--il-*` variables and
  optional `.il-*` component classes. Dark mode follows the OS via
  `prefers-color-scheme`; force it with `<html data-theme="dark">`.
  Load the three Google Fonts. Wire the favicons/manifest from `icons/web/`.
- **iOS / macOS** — add `theme/ios-ILColor.swift`; register the three fonts.
  Use `icons/ios` in the Asset Catalog; drop in `icons/macos/InterlinedList.icns` for the app icon.
- **Android** — split `android-colors.xml` into `values/` + `values-night/`,
  or use `android-Color.kt` with Compose. Import the adaptive layers from
  `icons/android` (`ic_launcher_foreground` + `ic_launcher_background`).
- **Windows** — wire `icons/windows/InterlinedList.ico` (multi-size 16–256) as the app/exe icon.
- **Linux** — install `icons/linux` into the hicolor theme dirs + `logo/logo-icon.svg` as the scalable icon.

> **New teammate?** See `HANDOFF.md` for exactly which files to give each team
> and copy-paste Claude starter prompts.

## Rules of the mark

- Keep clear space around the mark ≥ 25% of its width.
- App icons sit on the **soft-sand tile** so all three mark colors read; the
  near-black tile ships for dark home screens. Don't place the mark directly
  on saturated teal (the teal strokes disappear).
- Wordmark: "Interlined" in text color, "List" in `#4FD09C` (dark) / `#2FA877` (light).

_See `guidelines/brand-guidelines.html` for the full visual reference._
