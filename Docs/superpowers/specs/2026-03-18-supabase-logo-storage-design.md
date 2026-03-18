# Supabase Logo Storage — Remote Brand Logos

**Date:** 2026-03-18
**Status:** Approved

## Problem

Bank logos (44 imagesets, 1.3 MB) are bundled in Assets.xcassets. Adding hundreds of KZ/CIS brand logos from user's Figma library would balloon app size to 10-30 MB. Need remote storage with on-demand loading.

## Solution

Add `SupabaseLogoProvider` as the first provider in the waterfall chain. Migrate all bank logos from Assets.xcassets to Supabase Storage. Remove `BankLogo` enum, `LocalLogoProvider`, and all local logo assets entirely (no users — no migration needed).

## Architecture

### Updated Provider Chain

```
SupabaseLogoProvider → LogoDevProvider → GoogleFaviconProvider → LettermarkProvider
```

Supabase is first — gives full control over what logo is shown. If a logo exists in Supabase, it wins. Otherwise falls back to logo.dev → Google Favicon → Lettermark.

`LocalLogoProvider` is removed.

### SupabaseLogoProvider

`nonisolated final class` conforming to `LogoProvider`.

**URL formation:**
```
{SUPABASE_LOGOS_BASE_URL}/{domain}.png
```

Example: `https://abc123.supabase.co/storage/v1/object/public/logos/kaspi.kz.png`

**Configuration:** Base URL read from `Info.plist` key `SUPABASE_LOGOS_BASE_URL`. If key is missing or empty — provider returns nil immediately (chain continues).

**Validation:**
- HTTP 200 required
- Response data > 100 bytes (empty/error responses are tiny)
- Timeout: 5 seconds (custom URLSession configuration)

### Supabase Storage Setup (manual, outside code)

- Bucket: `logos` — public read access (no auth needed)
- Files: `{domain}.png` — flat structure, 256x256 PNG
- User exports from Figma manually, uploads to Supabase dashboard
- Cache-Control header set by Supabase — URLSession respects it automatically

### Info.plist Configuration

New key: `SUPABASE_LOGOS_BASE_URL`
```
https://{project-id}.supabase.co/storage/v1/object/public/logos
```

Same pattern as existing `LOGO_DEV_PUBLIC_KEY` — no hardcoded URLs, can switch between dev/prod.

## Legacy Cleanup

No users exist — full cleanup with no migration.

### Files to Delete (3)

| File | Reason |
|------|--------|
| `Services/Core/LocalLogoProvider.swift` | Replaced by SupabaseLogoProvider |
| `Utils/BankLogo.swift` | No longer needed — all logos via domain-based providers |
| `Utils/BrandLogoDisplayHelper.swift` | References BankLogo — obsolete |

### Assets to Delete

All bank logo imagesets from `Assets.xcassets` (44 imagesets, ~1.3 MB). These logos will be served from Supabase instead.

### IconSource Simplification

Remove `.bankLogo(BankLogo)` case. Enum becomes:

```swift
enum IconSource: Codable, Equatable, Hashable {
    case sfSymbol(String)
    case brandService(String) // domain-based, loaded via provider chain
}
```

Update `displayIdentifier`, `from(displayIdentifier:)`, and Codable conformance to remove `bank:` prefix handling.

### ServiceLogoEntry Simplification

Remove `bankLogo: BankLogo?` field. Remove `iconSource` computed property — all entries use `.brandService(domain)`. Remove the `init` overload that accepts `bankLogo:`.

Bank entries in `ServiceLogoRegistry` keep their domains (`kaspi.kz`, `altynbank.kz`, etc.) — SupabaseLogoProvider resolves them.

## File Changes

### New Files (1)

| File | Location | Purpose |
|------|----------|---------|
| `SupabaseLogoProvider.swift` | Services/Core/ | Supabase Storage logo fetcher |

### Modified Files

| File | Changes |
|------|---------|
| `LogoService.swift` | Replace LocalLogoProvider with SupabaseLogoProvider in chain. Supabase is first. |
| `IconSource.swift` | Remove `.bankLogo` case, update Codable/displayIdentifier |
| `ServiceLogo.swift` | Remove `bankLogo: BankLogo?` field, simplify bank entries to plain `ServiceLogoEntry` |
| `IconView.swift` | Remove `.bankLogo` rendering branch |
| `IconPickerView.swift` | Remove `LogoItem.bank` case, all items are `.service(ServiceLogoEntry)` |
| `Info.plist` | Add `SUPABASE_LOGOS_BASE_URL` key |
| `Assets.xcassets` | Delete all bank logo imagesets |

### Deleted Files (3)

- `Services/Core/LocalLogoProvider.swift`
- `Utils/BankLogo.swift`
- `Utils/BrandLogoDisplayHelper.swift`

### Unchanged

- `LogoDevConfig.swift` — as-is
- `GoogleFaviconProvider.swift` — as-is
- `LettermarkProvider.swift` — as-is (uses ServiceLogoRegistry, not BankLogo)
- `LogoDiskCache.swift` — as-is
- `LogoProvider.swift` — as-is (protocol unchanged)

## Edge Cases

- **Supabase URL not configured:** Provider returns nil, chain falls through to LogoDev
- **Logo not yet uploaded to Supabase:** Falls through to LogoDev → Google Favicon → Lettermark
- **Supabase down:** 5s timeout, falls through gracefully
- **No internet:** All remote providers return nil → Lettermark (always succeeds)
- **Disk cache has old local logo:** Still works — cache key is domain-based, cached images persist

## Testing Strategy

- Unit test SupabaseLogoProvider with mock URLSession
- Unit test chain order: verify Supabase is called first
- Unit test IconSource without `.bankLogo` case — Codable round-trip
- Build verification: no references to BankLogo remain (grep)
- Manual: upload a logo to Supabase, verify it appears in app
