# Tapir

[中文](README.md) · **English**

<p align="center">
  <img src="Resources/branding/tapir-icon-v4.png" width="180" alt="Tapir icon">
</p>

> **Eat the clicks you forget.**
> A macOS menu-bar app that quietly observes everything you click — apps, buttons, time of day — and at the end of the day shows you a beautiful screen-wide click heatmap, leaderboards, and an hourly timeline.
>
> Pipeline: `CGEventTap` for global click capture → `Accessibility (AXUIElement)` for UI semantics → SQLite for storage → SwiftUI + Charts + a custom KDE renderer for the report.

All data lives **locally**. No network requests, ever.

<p align="center">
  <img src="docs/screenshots/heatmap-preview.png" alt="Tapir daily click heatmap shareable export" width="900">
</p>

<p align="center">
  <sub>
  ↑ <strong>This is a click heatmap of an entire Mac screen, accumulated over one day.</strong> Every glowing dot is one real mouse click; the brighter a region, the more clicks landed there.
  <br>
  The horizontal band along the top is the browser tab bar / system menu bar; the bright cluster at the bottom-left is the Dock; the scatter in the middle is the content area of various app windows.
  <br>
  <strong>Privacy-safe by design</strong>: no window titles, no button text, no URLs — only anonymous coordinates plus aggregate stats (total clicks, top app, peak hour).
  </sub>
</p>

> About the name: a tapir is a real animal whose name hides the word **tap** (as in *click*). In East Asian folklore, tapirs are said to eat the dreams you don't remember — a fitting metaphor for a tool that records the operations you don't notice yourself doing.

---

## Project layout

```
.
├── Package.swift
├── Sources/
│   ├── ClickInsightCore/          Low-level building blocks (legacy name; external brand = Tapir)
│   │   ├── Models.swift           ClickEvent / DailyReport / HeatPoint …
│   │   ├── Permissions.swift      Accessibility trust check
│   │   ├── EventTap.swift         CGEventTap wrapper
│   │   ├── ContextResolver.swift  NSWorkspace + AXUIElement at the click point
│   │   ├── Storage.swift          SQLite via system sqlite3, zero deps
│   │   └── Recorder.swift         Orchestrator (@MainActor, ObservableObject)
│   └── ClickInsightApp/           SwiftUI menu-bar app
│       ├── ClickInsightApp.swift  @main, MenuBarExtra + ReportWindow
│       ├── MenuBarView.swift      Menu-bar panel: today's count / toggle / permissions
│       ├── ReportWindow.swift     The main report window
│       ├── Charts.swift           ReportCard + leaderboards + timeline
│       ├── Heatmap.swift          KDE renderer (separable Gaussian + inferno palette)
│       └── Sharing.swift          Shareable composition + clipboard / PNG export
├── Resources/
│   ├── Info.plist                 LSUIElement + Accessibility usage description
│   └── branding/                  Tapir logo assets (SVG + PNGs)
└── scripts/
    ├── make-app.sh                Build + bundle + auto codesign + smart TCC reset
    ├── make-icon.sh               Source PNG/SVG → AppIcon.icns
    ├── svg-to-png.swift           Rasterize SVG to PNG using NSImage
    └── setup-identity.sh          Create a stable local code-signing identity (one-time)
```

## One-time setup (recommended)

```bash
bash scripts/setup-identity.sh     # Stable code-signing identity → TCC grants survive rebuilds
bash scripts/make-icon.sh          # Generate AppIcon.icns from the SVG source
bash scripts/make-app.sh           # Build + assemble Tapir.app
open Tapir.app
```

You can skip `setup-identity.sh` — without it the app still works, but every rebuild has a fresh code identity, so macOS treats it as a new app and re-prompts for Accessibility each time.

`scripts/make-app.sh` is smart about TCC:
- It remembers the last signing identity it used
- If the identity changed (e.g. you switched from ad-hoc to the stable one, or first run), it `tccutil reset`s the old grant and `pkill`s any running instance so the next launch is a clean re-grant
- If the identity is unchanged, TCC entries stick and you get **zero** re-prompts across rebuilds

## First launch

A small cursor glyph appears at the top-right of your menu bar (Tapir does not occupy the Dock). Click it:

1. **Accessibility**: tap "Grant" — macOS opens *Settings → Privacy & Security → Accessibility*. Flip the Tapir switch on.
2. **Start recording**: press the green button. A green dot means it's recording.

Re-open the menu-bar panel any time to see the live "Today's clicks" counter.

## The report

Menu bar → **Open report**. The window, top to bottom:

- **Five KPI tiles** — total clicks / left / right / top app / peak hour
- **Click heatmap** — a real Kernel Density Estimation render. SQL aggregates clicks into 4-px bins → float buffer → separable Gaussian blur (σ ≈ 7 screen px, sized to a typical click target) → sqrt dynamic-range compression → inferno colormap → CGImage. Includes screen-coordinate corner tags, a color-scale legend, and a **Share** menu (copy to clipboard / save as PNG).
- **Daily rhythm** — area + line chart of clicks per hour, with the peak hour automatically highlighted.
- **Top apps / Top UI elements** — leaderboard-style rows: rank + name + gradient bar + count + percentage.

The date picker lets you replay any past day.

## Sharing the heatmap

Share menu in the top-right of the heatmap card:

- **Copy image to clipboard** — paste straight into Notion / Slack / Twitter
- **Save as PNG…** — defaults to `ClickInsight-YYYY-MM-DD.png`

The shared image is an independent composition (not a window screenshot). It contains: branded header, large total-click number, the heatmap with legend, five summary stats, and a "data stays local" footer. Rendered at 2× retina via SwiftUI `ImageRenderer`.

## Where the data lives

```
~/Library/Application Support/ClickInsight/
└── events.db                     SQLite, table `clicks`
```

Query it directly:

```bash
sqlite3 ~/Library/Application\ Support/ClickInsight/events.db \
  "SELECT app_name, ax_role, ax_title, COUNT(*) FROM clicks
   WHERE ts > strftime('%s','now','start of day')
   GROUP BY 1,2,3 ORDER BY 4 DESC LIMIT 30;"
```

## Privacy boundaries

- Only subscribes to mouse-down events; keyboard content is **never** captured
- Does not screenshot or screen-record (the snapshot feature was deliberately removed to drop one permission ask)
- Zero network requests
- To wipe everything: `rm -rf ~/Library/Application\ Support/ClickInsight/`

## Known limits / good-first-issues

- Multi-display is rendered against the primary display's logical coords
- No "launch at login" yet (drop in a LaunchAgent or use `SMAppService`)
- No weekly / monthly aggregate views
- Some apps (Electron-y stacks, certain games) don't expose AX children — Tapir falls back to the role
- The menu-bar glyph is still the SF Symbol cursor; at 18 px a full tapir silhouette gets muddy. Replace with a custom SVG template glyph if you want full brand consistency.

## Brand assets

- `Resources/branding/tapir-icon.svg` — the vector source (Quiver-vectorized)
- `Resources/branding/AppIcon.icns` — built by `make-icon.sh`, dropped into `.app/Contents/Resources/`
- `Resources/branding/tapir-icon-v2/v3/v4/v5.png` — exploration history; v5 is the SVG raster, v4 the chosen AI source

To iterate on the logo: edit the SVG, run `bash scripts/make-icon.sh`, then `bash scripts/make-app.sh`.

## Development

```bash
swift build                # debug
swift run Tapir            # quick smoke test (no Info.plist → AX prompt copy will be missing)
```

Internal naming: the Swift target / executable / `CFBundleIdentifier` all still say `ClickInsight` to avoid resetting existing TCC grants. Public branding is always **Tapir**.

## License

MIT.
