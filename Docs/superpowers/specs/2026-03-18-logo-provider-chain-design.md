# Logo Provider Chain — Enhanced Brand Logo System

**Date:** 2026-03-18
**Status:** Approved

## Problem

logo.dev lacks coverage for Kazakhstani and CIS brands (Kaspi, Kolesa, Yandex Music, Ozon, Wildberries, telecom providers, etc.). Current search in IconPickerView only works by domain — no name-based lookup. Users see empty fallbacks for most local services.

## Solution

Waterfall chain of logo providers with unified protocol, expanded local service database with name→domain mapping, fuzzy name search, and Google Favicon + Lettermark as fallbacks.

## Architecture

### LogoProvider Protocol

```swift
protocol LogoProvider {
    var name: String { get }
    func fetchLogo(domain: String, size: CGFloat) async -> UIImage?
}
```

### Fallback Chain (priority order)

1. **LocalLogoProvider** — checks `BankLogo` assets (57 existing bank logos)
2. **LogoDevProvider** — existing logo.dev API (`img.logo.dev/{domain}?token={key}`)
3. **GoogleFaviconProvider** — `google.com/s2/favicons?domain={domain}&sz=128`
4. **LettermarkProvider** — generated UIImage with 1-2 letters + deterministic color

`LogoService.logoImage(brandName:)` iterates providers sequentially. First non-nil result is cached in existing two-tier cache (memory NSCache + disk PNG). Public API unchanged — all call sites work without modification.

### Chain Execution Flow

```
logoImage("kaspi.kz") called
  → LocalLogoProvider: check BankLogo assets → found? return UIImage
  → LogoDevProvider: fetch img.logo.dev/kaspi.kz → got image? return
  → GoogleFaviconProvider: fetch google.com/s2/favicons?domain=kaspi.kz&sz=128
      → response < 1KB or matches default globe → nil
      → valid image → return
  → LettermarkProvider: generate "KP" on colored background → return
```

## Expanded Local Database

### New ServiceCategory Cases

- `.localServices` — Kaspi Pay, Kolesa, Krisha, OLX.kz, 2GIS, Chocofamily, Glovo, Wolt, InDrive
- `.telecom` — Kcell, Beeline KZ, Tele2 KZ, Altel, Activ, Megaline
- `.cis` — Yandex Music, Kinopoisk, VK, Ozon, Wildberries, SberMarket, Tinkoff, MTS

### ServiceLogo Additions

Add `aliases: [String]` property to ServiceLogo for fuzzy search support. ~80-100 new entries.

Each entry: `rawValue` (domain) + `displayName` + `aliases` (cyrillic/latin variants).

Examples:
- `kaspi.kz` → displayName: "Kaspi Pay", aliases: ["каспи", "kaspi", "каспий"]
- `kolesa.kz` → displayName: "Kolesa.kz", aliases: ["колеса", "колёса"]
- `music.yandex.ru` → displayName: "Яндекс Музыка", aliases: ["yandex music", "яндекс"]

Existing 95 services unchanged.

## Enhanced Search in IconPickerView

### Two-Phase Search

**Phase 1 — Local fuzzy match (instant):**
- Filter `ServiceLogo` by `displayName` + `aliases` using `localizedCaseInsensitiveContains`
- Case-insensitive, supports Cyrillic and Latin
- Show up to 8 suggestions with logo previews
- No external libraries — database is small, O(N) scan is fast

**Phase 2 — Domain fallback (async):**
- If no local matches and input contains `.` → try as domain via LogoProvider chain
- If no `.` → try `{input}.com` and `{input}.kz` in parallel
- Show result in "Online" section below suggestions

### UI Changes in IconPickerView Logos Tab

- Search field remains as-is
- Below field: "Suggestions" section with fuzzy match results (up to 8)
- Below suggestions: "Online" section with direct domain search result
- Each suggestion: `IconView` + displayName, tap selects `.brandService(domain)`

## Google Favicon Provider

- **URL:** `https://www.google.com/s2/favicons?domain={domain}&sz=128`
- **Cost:** Free, no API key, no rate limits
- **Response:** PNG 128x128
- **Validation:** If response < 1KB or matches default globe icon → return nil (fall through to lettermark)
- **Timeout:** 5 seconds

## Lettermark Provider

- **Letter selection:** First 2 letters of displayName words. "Kaspi Pay" → "KP", "2GIS" → "2G", "Ozon" → "OZ". Single-word → first 2 chars.
- **Background color:** Deterministic from `CategoryColors` palette via hash of domain string (same brand always same color)
- **Text:** White, bold, centered
- **Shape:** Rounded rect with `cornerRadius = size * 0.2` (matches BrandLogoView)
- **Rendering:** `UIGraphicsImageRenderer`, cached after first generation

## Caching Strategy

All providers use existing `LogoDiskCache` + memory NSCache. Cache key includes provider suffix to allow upgrade:
- `{domain}_local.png`
- `{domain}_logodev.png`
- `{domain}_google.png`
- `{domain}_letter.png`

When a higher-priority provider returns a result for a domain that was previously cached by a lower-priority provider, the better image overwrites the old cache entry. The main cache key `{domain}.png` always stores the best available image.

## File Changes

### New Files (4)

| File | Location | Purpose |
|------|----------|---------|
| `LogoProvider.swift` | Services/Core/ | Protocol + chain orchestration logic |
| `LocalLogoProvider.swift` | Services/Core/ | BankLogo asset lookup |
| `GoogleFaviconProvider.swift` | Services/Core/ | Google Favicon API client |
| `LettermarkProvider.swift` | Services/Core/ | Letter-based icon generator |

### Modified Files (4)

| File | Changes |
|------|---------|
| `LogoService.swift` | Refactor to iterate `[LogoProvider]` chain instead of direct logo.dev call. Public API unchanged. |
| `ServiceLogo.swift` | Add `aliases: [String]` property, 3 new `ServiceCategory` cases, ~80-100 new KZ/CIS entries. |
| `LogoDevConfig.swift` | Extract URL formation into `LogoDevProvider`. Config retains Info.plist key reading. |
| `IconPickerView.swift` | Replace `OnlineSearchResultsView` with two-phase search (suggestions + online fallback). |

### Unchanged (backward compatible)

- `IconSource` enum — `.brandService(domain)` works as before
- `BrandLogoView` — calls `LogoService` as before
- `IconView` — no changes
- `LogoDiskCache` — no API changes
- All existing saved icons continue working
- `BrandLogoDisplayHelper` — no changes

## Edge Cases

- **logo.dev API key missing:** `LogoDevProvider` returns nil (chain continues to Google Favicon)
- **No internet:** All remote providers return nil → LettermarkProvider always succeeds
- **Empty search text:** Show category grid as today (no change)
- **Duplicate aliases:** Multiple services may match — show all, sorted by relevance (displayName exact match first, then alias match)
- **Domain with path/params:** Strip to base domain before querying providers

## Testing Strategy

- Unit test each provider in isolation with mock URLSession
- Unit test chain: verify fallback order (mock providers returning nil)
- Unit test fuzzy search: Cyrillic input, Latin input, partial match, no match
- Unit test LettermarkProvider: letter extraction, deterministic color
- UI test: search "каспи" → verify Kaspi Pay appears in suggestions
