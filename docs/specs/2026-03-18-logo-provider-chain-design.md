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
nonisolated protocol LogoProvider {
    var name: String { get }
    func fetchLogo(domain: String, size: CGFloat) async -> UIImage?
}
```

**Concurrency model:** Protocol is `nonisolated` — all conforming types opt out of implicit MainActor. `LocalLogoProvider` and `LettermarkProvider` are synchronous wrappers (return immediately). `LogoDevProvider` and `GoogleFaviconProvider` are `nonisolated final class` — network calls via `URLSession.shared.data(from:)` suspend off MainActor naturally. `LogoService.logoImage(brandName:)` remains `@MainActor` and calls the chain via `await` — safe because URLSession suspends, not blocks.

### Fallback Chain (priority order)

1. **LocalLogoProvider** — checks `BankLogo` assets (57 existing bank logos)
2. **LogoDevProvider** — existing logo.dev API (`img.logo.dev/{domain}?token={key}`), 5s timeout
3. **GoogleFaviconProvider** — `google.com/s2/favicons?domain={domain}&sz=128`, 5s timeout
4. **LettermarkProvider** — generated UIImage with 1-2 letters + deterministic color

`LogoService.logoImage(brandName:)` iterates providers sequentially. First non-nil result is cached. The existing `LogoDevConfig.isAvailable` guard is **removed** from both `LogoService.logoImage` and `LogoService.prefetch` — the chain always runs. `LogoDevProvider` internally checks `LogoDevConfig.isAvailable` and returns nil immediately if no API key, allowing the chain to continue to Google Favicon/Lettermark.

**Domain normalization:** `LogoService` resolves `brandName` to domain before cache operations and chain invocation. Resolution order: (1) check `ServiceLogoRegistry.domainMap[brandName.lowercased()]` for direct domain match, (2) check `aliasMap` for display name/alias match → extract domain, (3) use `brandName` as-is (assumed to be a domain). This ensures a single cache key per domain regardless of whether the caller passes "Kaspi Pay" or "kaspi.kz".

**Signature change:** `logoImage(brandName:)` drops `throws` from its signature (`async -> UIImage?` instead of `async throws -> UIImage?`). The chain always succeeds — `LettermarkProvider` never fails. Each remote provider catches errors internally and returns nil. Call sites in `BrandLogoView` and elsewhere remove `try`/`try?`.

### Chain Execution Flow

```
logoImage("kaspi.kz") called
  → LocalLogoProvider: check BankLogo assets → found? return UIImage
  → LogoDevProvider: LogoDevConfig.isAvailable? no → nil / yes → fetch (5s timeout)
  → GoogleFaviconProvider: fetch google.com/s2/favicons?domain=kaspi.kz&sz=128 (5s timeout)
      → response < 1KB or image dimensions ≤ 16x16 → nil
      → valid image → return
  → LettermarkProvider: generate "KP" on colored background → return (always succeeds)
```

## Expanded Local Database

### New ServiceCategory Cases

- `.localServices` — Kaspi Pay, Kolesa, Krisha, OLX.kz, 2GIS, Chocofamily, Glovo, Wolt, InDrive
- `.telecom` — Kcell, Beeline KZ, Tele2 KZ, Altel, Activ, Megaline
- `.cis` — Yandex Music, Kinopoisk, VK, Ozon, Wildberries, SberMarket, Tinkoff, MTS

### ServiceLogo Refactor: Enum → Struct Registry

Convert `ServiceLogo` from enum to struct-based registry to avoid massive switch statements for aliases.

```swift
struct ServiceLogoEntry: Sendable {
    let domain: String        // "kaspi.kz"
    let displayName: String   // "Kaspi Pay"
    let category: ServiceCategory
    let aliases: [String]     // ["каспи", "kaspi", "каспий"]
}

nonisolated enum ServiceLogoRegistry {
    static let allServices: [ServiceLogoEntry] = [ /* 175+ entries */ ]

    // Domain lookup: "kaspi.kz" → entry
    static let domainMap: [String: ServiceLogoEntry] = {
        Dictionary(uniqueKeysWithValues: allServices.map { ($0.domain.lowercased(), $0) })
    }()

    // Alias + displayName lookup, built once
    static let aliasMap: [String: ServiceLogoEntry] = {
        var map: [String: ServiceLogoEntry] = [:]
        for entry in allServices {
            map[entry.domain.lowercased()] = entry
            map[entry.displayName.lowercased()] = entry
            for alias in entry.aliases {
                map[alias.lowercased()] = entry
            }
        }
        return map
    }()

    static func services(for category: ServiceCategory) -> [ServiceLogoEntry] { ... }
    static func search(query: String) -> [ServiceLogoEntry] { ... }

    /// Resolve any input (domain, displayName, alias) to a domain string
    static func resolveDomain(from input: String) -> String {
        if let entry = domainMap[input.lowercased()] { return entry.domain }
        if let entry = aliasMap[input.lowercased()] { return entry.domain }
        return input // assume raw domain
    }
}
```

Existing 95 services migrated to struct entries. ~80-100 new KZ/CIS entries added.

**Migration:** `ServiceLogo` enum retained as deprecated typealias for backward compatibility with `IconPickerView` category filtering. All new code uses `ServiceLogoRegistry`.

## Enhanced Search in IconPickerView

### Two-Phase Search

**Phase 1 — Local fuzzy match (instant):**
- Filter `ServiceLogoRegistry.allServices` by `displayName` + `aliases` using `localizedCaseInsensitiveContains`
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
- **Validation:** Response < 1KB → return nil. Image dimensions ≤ 16x16 → return nil (Google returns 16x16 for unknown domains even when `sz=128` is requested). No pixel-level "default globe" comparison — too fragile.
- **Timeout:** 5 seconds (via custom `URLSession` configuration)

## Lettermark Provider

- **Letter selection:** First letter of each word in displayName, up to 2. "Kaspi Pay" → "KP", "2GIS" → "2G", "Ozon" → "OZ". Single-word → first 2 chars. Always Latin — displayName is the source (not aliases).
- **Background color:** Deterministic from `CategoryColors` palette via hash of domain string (same brand always same color)
- **Text:** White, bold, centered
- **Shape:** Rounded rect with `cornerRadius = size * 0.2` (matches BrandLogoView)
- **Rendering:** `UIGraphicsImageRenderer`, cached after first generation

## Caching Strategy

Single cache key per domain: `{domain}.png`. The chain returns the best available result by priority order — no need for provider-specific keys. If a higher-priority provider later becomes available (e.g., logo.dev adds a brand), the next uncached fetch will overwrite the old entry naturally (cache has TTL via disk file modification date, or manual invalidation).

Memory: existing `NSCache` (200 image limit, 50MB). Disk: existing `LogoDiskCache` in Application Support/logos/.

## File Changes

### New Files (4)

| File | Location | Purpose |
|------|----------|---------|
| `LogoProvider.swift` | Services/Core/ | `nonisolated` protocol + chain orchestration logic |
| `LocalLogoProvider.swift` | Services/Core/ | BankLogo asset lookup (`nonisolated final class`) |
| `GoogleFaviconProvider.swift` | Services/Core/ | Google Favicon API client (`nonisolated final class`) |
| `LettermarkProvider.swift` | Services/Core/ | Letter-based icon generator (`nonisolated final class`) |

**Location rationale:** Existing logo files (`LogoService`, `LogoDevConfig`, `LogoDiskCache`) are already in `Services/Core/`. Keeping new providers co-located for consistency.

### Modified Files (5)

| File | Changes |
|------|---------|
| `LogoService.swift` | Refactor to iterate `[LogoProvider]` chain. **Remove** `LogoDevConfig.isAvailable` guard from both `logoImage` and `prefetch` — chain always runs. Extract logo.dev fetch logic into `LogoDevProvider`. Change signature: `logoImage(brandName:)` drops `throws` (`async -> UIImage?`). Add domain normalization via `ServiceLogoRegistry.resolveDomain`. |
| `BrandLogoView.swift` | **Drop `AsyncImage` dual-path rendering.** Simplify to only use `LogoService.logoImage(brandName:)` chain result. Remove `logoURL` state and `LogoDevConfig.isAvailable` checks. |
| `ServiceLogo.swift` | Refactor from enum to struct registry (`ServiceLogoRegistry`). Add `aliases: [String]`, 3 new `ServiceCategory` cases, ~80-100 new KZ/CIS entries. Retain deprecated enum for backward compat. |
| `LogoDevConfig.swift` | Retain Info.plist key reading and `isAvailable` check. URL formation moved to `LogoDevProvider`. |
| `IconPickerView.swift` | Replace `OnlineSearchResultsView` with two-phase search (suggestions + online fallback). Update category grid sections to use `ServiceLogoRegistry.services(for:)` returning `[ServiceLogoEntry]` instead of `ServiceLogo` enum cases. Use `ServiceLogoRegistry.search()` for fuzzy search. |

### Unchanged (backward compatible)

- `IconSource` enum — `.brandService(domain)` works as before
- `IconView` — no changes
- `LogoDiskCache` — no API changes
- All existing saved icons continue working
- `BrandLogoDisplayHelper` — benefits transitively through `LogoService` chain; no direct changes needed

## Edge Cases

- **logo.dev API key missing:** `LogoDevProvider` returns nil internally (chain continues to Google Favicon)
- **No internet:** All remote providers return nil → LettermarkProvider always succeeds
- **Empty search text:** Show category grid as today (no change)
- **Duplicate aliases:** Multiple services may match — show all, sorted by relevance (displayName exact match first, then alias match)
- **Domain with path/params:** Strip to base domain before querying providers
- **Slow logo.dev response:** 5-second timeout per remote provider prevents chain from hanging

## Testing Strategy

- Unit test each provider in isolation with mock URLSession
- Unit test chain: verify fallback order (mock providers returning nil)
- Unit test fuzzy search: Cyrillic input, Latin input, partial match, no match
- Unit test LettermarkProvider: letter extraction, deterministic color
- Unit test GoogleFaviconProvider: size threshold validation (< 1KB, ≤ 16x16 rejection)
- UI test: search "каспи" → verify Kaspi Pay appears in suggestions
