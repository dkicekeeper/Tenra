# Design: Inter Variable Font Migration

**Date:** 2026-02-21
**Status:** Approved

## Goal

Replace 18 static Overpass `.ttf` files with 2 Inter variable font files, reducing bundle size by ~68% and enabling automatic optical-size optimisation per text size.

## Current State

- **Font files:** 18 × Overpass `.ttf` (~3 MB total)
- **Registered in UIAppFonts:** 4 (Regular, Medium, SemiBold, Bold)
- **Typography system:** `AppTypography` enum in `AppTheme.swift`, 12 levels
- **Weight encoding:** baked into PostScript name (`"Overpass-Bold"`, etc.)
- **Consumers:** 77+ view files, all via `AppTypography.*` — no direct font references

## Target State

- **Font files:** 2 × Inter variable `.ttf` (~960 KB total, -68%)
  - `Inter[opsz,wght].ttf` — upright, weight axis 100–900, optical size 14–32 pt
  - `Inter-Italic[opsz,wght].ttf` — italic, same axes
- **Registered in UIAppFonts:** 2
- **Weight encoding:** via `.weight()` SwiftUI modifier on `Font.custom`
- **Optical size:** automatic — iOS passes `pointSize` as `opsz` value; no extra code needed
- **Public API:** unchanged — all 77+ view files stay untouched

## Architecture

### Font Constants (AppTheme.swift)

```swift
// Before
private enum AppOverpassFont {
    static let regular  = "Overpass-Regular"
    static let medium   = "Overpass-Medium"
    static let semibold = "Overpass-SemiBold"
    static let bold     = "Overpass-Bold"
}

// After
private enum AppInterFont {
    static let family       = "Inter"
    static let familyItalic = "Inter-Italic"
}
```

### Typography Levels (AppTypography)

All 12 levels migrate from name-encoded weight to `.weight()` modifier:

```swift
// Before
static let h1 = Font.custom(AppOverpassFont.bold,     size: 34, relativeTo: .largeTitle)
static let h2 = Font.custom(AppOverpassFont.semibold, size: 28, relativeTo: .title)
static let body = Font.custom(AppOverpassFont.regular, size: 18, relativeTo: .body)

// After
static let h1 = Font.custom(AppInterFont.family, size: 34, relativeTo: .largeTitle).weight(.bold)
static let h2 = Font.custom(AppInterFont.family, size: 28, relativeTo: .title).weight(.semibold)
static let body = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.regular)
```

Weight mapping per level:

| Level         | Weight   | Size | Dynamic Type  |
|---------------|----------|------|---------------|
| h1            | bold     | 34   | .largeTitle   |
| h2            | semibold | 28   | .title        |
| h3            | semibold | 24   | .title2       |
| h4            | semibold | 20   | .title3       |
| bodyLarge     | medium   | 18   | .body         |
| body          | regular  | 18   | .body         |
| bodySmall     | regular  | 16   | .subheadline  |
| caption       | regular  | 14   | .caption      |
| captionEmphasis | medium | 14   | .caption      |
| caption2      | regular  | 12   | .caption2     |
| label         | medium   | 16   | .subheadline  |
| amount        | semibold | 18   | .body         |

### Info.plist

```xml
<!-- Before -->
<key>UIAppFonts</key>
<array>
    <string>Overpass-Regular.ttf</string>
    <string>Overpass-Medium.ttf</string>
    <string>Overpass-SemiBold.ttf</string>
    <string>Overpass-Bold.ttf</string>
</array>

<!-- After -->
<key>UIAppFonts</key>
<array>
    <string>Inter[opsz,wght].ttf</string>
    <string>Inter-Italic[opsz,wght].ttf</string>
</array>
```

### Xcode Project (project.pbxproj)

- Remove 18 PBXFileReference + 18 PBXBuildFile entries for Overpass files
- Add 2 PBXFileReference + 2 PBXBuildFile entries for Inter files

## What Does NOT Change

- Public `AppTypography` API (`h1`, `body`, `amount`, etc.)
- Font sizes
- Dynamic Type support (`relativeTo:` parameter)
- Semantic aliases (`screenTitle`, `sectionHeader`, etc.)
- All 77+ view files consuming `AppTypography.*`

## Files Changed

| File | Change |
|------|--------|
| `Fonts/` directory | Remove 18 Overpass .ttf; add 2 Inter .ttf |
| `AIFinanceManager/Info.plist` | Update UIAppFonts array |
| `AIFinanceManager/Utils/AppTheme.swift` | Replace AppOverpassFont → AppInterFont, update AppTypography |
| `AIFinanceManager.xcodeproj/project.pbxproj` | Update font file references and build files |

## Prerequisites (Manual Step)

User must download Inter variable font from [Google Fonts — Inter](https://fonts.google.com/specimen/Inter):
1. Click **Download family**
2. In the zip, locate `static/` vs root — the variable font files are in the root:
   - `Inter[opsz,wght].ttf`
   - `Inter-Italic[opsz,wght].ttf`
3. Place both in the project's `Fonts/` directory before implementation begins

## Metrics

| Metric | Before | After |
|--------|--------|-------|
| Font files | 18 | 2 |
| Bundle font size | ~3 MB | ~960 KB |
| UIAppFonts entries | 4 | 2 |
| Weight range | 4 discrete | 100–900 continuous |
| Optical size | None | Auto (14–32 pt) |
| View files changed | — | 0 |
