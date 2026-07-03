# InterlinedList — Handoff & Integration Guide

How to route this kit to each team and get them productive fast in
**Claude-enabled projects** (Claude Code, or a Claude project with these files
attached as knowledge). The pattern is the same everywhere:

> **The 3-step pattern**
> 1. Create the team's project and drop in the **subset of `brand-kit/` listed below**.
> 2. Add a short **`CLAUDE.md`** (project instructions) that points Claude at
>    `theme/tokens.json` as the source of truth and `guidelines/brand-guidelines.html`
>    as the visual reference — and says "use these tokens, do not invent colors, type, or spacing."
> 3. Paste the **starter prompt** given for that team.

`theme/tokens.json` is the canonical, machine-readable source. Every platform
file (`interlinedlist-theme.css`, `android-colors.xml`, `android-Color.kt`,
`ios-ILColor.swift`) is derived from it — if a value ever conflicts, tokens.json wins.

Brand one-liner to include in every project's CLAUDE.md:

> InterlinedList uses the **Strata** system: teal `#184860` structure, green
> `#2FA877` actions, amber `#F0A830` for live/Dig, soft-sand light `#F4EEE2` and
> near-black dark `#121317`. Type: Space Grotesk (display) / Manrope (body) /
> JetBrains Mono (time & meta). Sharp corners (3–4px), 4pt spacing grid.
> Dark mode follows the OS. Never introduce colors, fonts, or radii outside the tokens.

---

## 1 · React Web Site Team

**Provide:**
- `theme/interlinedlist-theme.css` (variables + `prefers-color-scheme` + `.il-*` components)
- `theme/tokens.json`
- `logo/logo-icon.svg` (use inline/as `<img>`; scales crisply)
- `icons/web/` (favicons 16/32/48, `apple-touch-icon-180`, `icon-192`, `icon-512`, `maskable-512`, dark favicon)
- `guidelines/brand-guidelines.html`

**CLAUDE.md pointers:** "Import `interlinedlist-theme.css` once at the root. Style
everything with the `--il-*` custom properties; dark mode is automatic via
`prefers-color-scheme`, and `<html data-theme="dark|light">` forces it (wire this
to a Settings toggle). Load the 3 Google Fonts. Never hard-code hex values."

**Starter prompt:** "Re-theme the site to Strata using `interlinedlist-theme.css`.
Start with the feed: masthead (teal), left nav, color-edged post cards
(teal/green/amber left border), right rail with the stream-clock widget and
trending tags. Add a Light/Dark/System switch in Settings. Wire the favicons and
web manifest from `icons/web/`."

**Deliverables:** themed feed, thread, profile, compose, settings, auth;
`site.webmanifest` referencing the web icons; a working theme toggle.

---

## 2 · iOS App Team

**Provide:**
- `theme/ios-ILColor.swift`
- `theme/tokens.json`
- `icons/ios/` (`AppIcon-*.png` 1024→40 + `AppIcon-dark-1024.png`)
- `logo/logo-icon.svg` (in-app mark) + `guidelines/brand-guidelines.html`

**CLAUDE.md pointers:** "Use `ILColor` for all colors — they adapt to light/dark
via `UITraitCollection` automatically. Register Space Grotesk, Manrope, JetBrains
Mono and reference them via `ILType`. Use `ILMetric` for radius/spacing. Add the
iOS PNGs to an `AppIcon` image set in the Asset Catalog (include the dark 1024 as
the dark appearance)."

**Starter prompt:** "Build the SwiftUI feed with Strata: teal nav bar, color-edged
post rows, amber Dig button, bottom tab bar with a green compose FAB. Timestamps in
JetBrains Mono (military Zulu). Support Dynamic Type and dark mode."

**Deliverables:** themed feed/thread/profile/compose, `AppIcon` set installed,
fonts bundled and registered in `Info.plist`.

---

## 3 · macOS App Team

**Provide:**
- `theme/ios-ILColor.swift` (shared SwiftUI tokens — works on macOS)
- `theme/tokens.json`
- `icons/macos/InterlinedList.icns` (ready to drop in) + the `icon-*.png` sources
- `logo/logo-icon.svg` + `guidelines/brand-guidelines.html`

**CLAUDE.md pointers:** "Set `InterlinedList.icns` as the app icon in the target's
General tab. Use `ILColor` tokens; the desktop window uses the 10px radius
(`ILMetric.radiusLg`) with traffic-light chrome. Provide a teal icon sidebar."

**Starter prompt:** "Build the macOS window: traffic-light title bar showing the
subtle stream clock, a teal icon sidebar, and the color-edged feed. Match the
macOS surface in the design doc."

**Deliverables:** themed window + sidebar, `.icns` installed, light/dark support.

---

## 4 · Windows App Team

**Provide:**
- `icons/windows/InterlinedList.ico` (multi-size 16–256) + `icon-*.png` sources
- `theme/tokens.json`
- `logo/logo-icon.svg` + `guidelines/brand-guidelines.html`
- (If WinUI/XAML) generate a `Colors.xaml` from tokens.json — ask Claude to.

**CLAUDE.md pointers:** "App icon is `InterlinedList.ico`. Build the color
resource dictionary from `tokens.json` (light + dark). Title bar uses the deep-teal
`#0C2C3A`; right-aligned min/max/close. Sharp 4px card corners."

**Starter prompt:** "Theme the Windows (WinUI/Electron) app to Strata from
`tokens.json`: teal title bar, color-edged feed cards, green primary buttons, amber
live/Dig. Wire `InterlinedList.ico` as the executable and window icon. Respect the
OS light/dark setting."

**Deliverables:** themed shell, `.ico` wired, generated color dictionary,
dark-mode following the system.

---

## 5 · Linux App Team

**Provide:**
- `icons/linux/` (`icon-*.png` 512→48, hicolor sizes) + `logo/logo-icon.svg`
- `theme/tokens.json`
- `theme/interlinedlist-theme.css` (if the app is web-tech / GTK-WebKit / Electron)
- `guidelines/brand-guidelines.html`

**CLAUDE.md pointers:** "Install PNGs into `hicolor/<size>/apps/interlinedlist.png`
and the SVG into `hicolor/scalable/apps/interlinedlist.svg`; ship a `.desktop`
entry. For GTK/Qt, generate a theme/QSS or GTK CSS from `tokens.json`. Window
controls are left-aligned on GNOME; body is identical to other desktops."

**Starter prompt:** "Package the Linux app with Strata branding: install the
hicolor icon set + scalable SVG, write the `.desktop` file, and generate the
GTK/Qt stylesheet from `tokens.json` with light/dark variants."

**Deliverables:** hicolor icon install + `.desktop`, generated stylesheet,
light/dark parity.

---

## 6 · Android App Team

**Provide:**
- `theme/android-colors.xml` (View system) **and** `theme/android-Color.kt` (Compose)
- `theme/tokens.json`
- `icons/android/` (`ic_launcher-*.png` + `ic_launcher_foreground-*` + `ic_launcher_background-512`)
- `logo/logo-icon.svg` + `guidelines/brand-guidelines.html`

**CLAUDE.md pointers:** "Split `android-colors.xml` into `values/colors.xml` +
`values-night/` overrides, or use `android-Color.kt` with a Compose
`lightColorScheme`/`darkColorScheme`. Build the adaptive launcher icon from
`ic_launcher_foreground` + `ic_launcher_background` (mipmap-anydpi-v26). Register
the three fonts in `res/font`."

**Starter prompt:** "Theme the Android app to Strata with Material 3: map
`android-Color.kt` into light/dark color schemes, build the adaptive launcher icon
from the provided fg/bg layers, and lay out the feed with color-edged cards, a
green compose FAB, and JetBrains Mono timestamps."

**Deliverables:** M3 theme (light + night), adaptive launcher icon, fonts,
themed feed/compose.

---

## 7 · Documentation Team

**Provide:**
- The **entire `brand-kit/`** (they document all of it)
- `guidelines/brand-guidelines.html` (canonical visual reference)
- `theme/tokens.json` + `README.md` + this `HANDOFF.md`
- The interactive design doc (`InterlinedList Redesign` — screenshots or the live file)

**CLAUDE.md pointers:** "Treat `tokens.json` as the single source of truth. When
documenting a token, show its light and dark value and its role. Keep every code
sample in sync with the platform files in `theme/`."

**Starter prompt:** "Produce developer docs for the Strata design system: a color
reference (roles, light/dark, contrast notes), the type scale, spacing/radius,
component specs (button, tag, post card, Dig button, input), and per-platform
'getting started' pages that mirror `HANDOFF.md`. Export the guidelines to PDF."

**Deliverables:** hosted docs site or PDF, per-platform quick-starts, changelog
convention tied to `tokens.json` versions.

---

## 8 · Marketing Team

**Provide:**
- `logo/logo-icon.svg` (primary, scalable) + `logo/logo-icon-master.png`
- `theme/tokens.json` (brand colors + type) + `guidelines/brand-guidelines.html`
- `icons/` (for store listings, social avatars, favicons)

**CLAUDE.md pointers:** "Marketing may use the brand colors expressively but must
keep the mark rules (clear space ≥25%, sand or near-black backgrounds only, never
recolor). Headlines in Space Grotesk, body in Manrope, timestamps/labels in
JetBrains Mono. The tagline is 'Ordering streams across the chaos.'"

**Starter prompt:** "Using the Strata palette and fonts, design launch assets:
social avatars/banners from `logo-icon.svg`, an app-store screenshot set that
matches the in-app look, and a one-page brand overview. Keep to the token colors
and the mark usage rules."

**Deliverables:** social kit (avatars/banners), store screenshots, launch
one-pager — all on-brand.

---

### File-to-team quick map

| File | Web | iOS | macOS | Win | Linux | Android | Docs | Mktg |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| tokens.json | ● | ● | ● | ● | ● | ● | ● | ● |
| interlinedlist-theme.css | ● | | | ○ | ○ | | ● | |
| ios-ILColor.swift | | ● | ● | | | | ● | |
| android-colors.xml / .kt | | | | | | ● | ● | |
| logo-icon.svg | ● | ● | ● | ● | ● | ● | ● | ● |
| icons/web | ● | | | | | | ● | ● |
| icons/ios | | ● | | | | | ● | |
| InterlinedList.icns | | | ● | | | | ● | |
| InterlinedList.ico | | | | ● | | | ● | |
| icons/linux | | | | | ● | | ● | |
| icons/android | | | | | | ● | ● | |
| guidelines.html | ● | ● | ● | ● | ● | ● | ● | ● |

● = provide · ○ = provide if the app is web-tech (Electron/WebView)
