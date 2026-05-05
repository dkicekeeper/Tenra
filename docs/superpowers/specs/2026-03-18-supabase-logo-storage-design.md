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

No users exist — full cleanup with no migration. User will delete app data on device before running new build.

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

Update `displayIdentifier`, `from(displayIdentifier:)`, `migrate()`, and Codable conformance to remove `bank:` prefix handling.

### ServiceLogoEntry Simplification

Remove `bankLogo: BankLogo?` field. Remove `iconSource` computed property — all entries use `.brandService(domain)`. Remove the `init` overload that accepts `bankLogo:`.

Bank entries in `ServiceLogoRegistry` keep their domains (`kaspi.kz`, `altynbank.kz`, etc.) — SupabaseLogoProvider resolves them.

### UniversalRow.IconConfig Cleanup

Remove `IconConfig.bankLogo(_ logo: BankLogo, ...)` static method. Callers use `.custom(source:, style:)` with `.brandService(domain)` instead. Remove preview code referencing `BankLogo`.

### IconStyle Factory Rename

Rename `IconStyle.bankLogo(size:)` → `IconStyle.roundedLogo(size:)` and `IconStyle.bankLogoLarge(size:)` → `IconStyle.roundedLogoLarge(size:)`. These are visual style presets (rounded square), not tied to BankLogo enum.

## File Changes

### New Files (1)

| File | Location | Purpose |
|------|----------|---------|
| `SupabaseLogoProvider.swift` | Services/Core/ | Supabase Storage logo fetcher (`nonisolated final class`, dedicated URLSession with 5s timeout) |

### Deleted Files (3)

- `Services/Core/LocalLogoProvider.swift`
- `Utils/BankLogo.swift`
- `Utils/BrandLogoDisplayHelper.swift`

### Modified Files — Production Code

| File | Changes |
|------|---------|
| `LogoService.swift` | Replace LocalLogoProvider with SupabaseLogoProvider in chain. Supabase first. |
| `IconSource.swift` | Remove `.bankLogo` case, update Codable/displayIdentifier/migrate |
| `ServiceLogo.swift` | Remove `bankLogo: BankLogo?` field, remove `iconSource` property, simplify bank entries. Delete legacy `ServiceLogo` enum (dead code). |
| `IconView.swift` | Remove `.bankLogo` rendering branch and `bankLogoView` method |
| `IconPickerView.swift` | Remove `LogoItem.bank` case, all items are `.service(ServiceLogoEntry)` |
| `UniversalRow.swift` | Remove `IconConfig.bankLogo(...)` method, update to `.custom(source:, style:)` |
| `IconStyle.swift` | Rename `bankLogo()` → `roundedLogo()`, `bankLogoLarge()` → `roundedLogoLarge()` |
| `StaticSubscriptionIconsView.swift` | Remove `.bankLogo` switch case |
| `LoansCardView.swift` | Remove `.bankLogo` switch case |
| `LoanPayAllView.swift` | Replace `.bankLogo` style reference |
| `AccountEntity+CoreDataClass.swift` | Remove `BankLogo(rawValue:)` fallback migration, use domain strings |
| `RecurringSeriesEntity+CoreDataClass.swift` | Remove `BankLogo(rawValue:)` fallback migration |
| `AccountRepository.swift` | Remove `BankLogo.none.rawValue` references |
| `RecurringRepository.swift` | Remove `.bankLogo` case pattern match |
| `Transaction.swift` | Remove `BankLogo` Codable decoder fallback |
| `RecurringTransaction.swift` | Remove `BankLogo` Codable decoder fallback |
| `Info.plist` | Add `SUPABASE_LOGOS_BASE_URL` key |
| `Assets.xcassets` | Delete all 44 bank logo imagesets |

### Modified Files — Preview Code Only

These files have `#Preview` blocks referencing `.bankLogo(.kaspi)` etc. Replace with `.brandService("kaspi.kz")`.

| File |
|------|
| `IconView+Previews.swift` |
| `TransactionCard.swift` |
| `TransactionCardComponents.swift` |
| `TransactionEditView.swift` |
| `AccountsManagementView.swift` |
| `AccountEditView.swift` |
| `DepositEditView.swift` |
| `LoanEditView.swift` |
| `LoanPaymentView.swift` |
| `LoanRateChangeView.swift` |
| `LoanEarlyRepaymentView.swift` |
| `DepositRateChangeView.swift` |
| `EditableHeroSection.swift` |
| `HeroSection.swift` |
| `AccountsCarousel.swift` |
| `UniversalRow.swift` (preview section) |

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
- **Old CoreData with BankLogo data:** User deletes app data before upgrading — no migration needed

## Testing Strategy

- Unit test SupabaseLogoProvider with mock URLSession
- Unit test chain order: verify Supabase is called first
- Unit test IconSource without `.bankLogo` case — Codable round-trip
- Build verification: `grep -rn "BankLogo" Tenra/ --include="*.swift"` returns 0 results
- Manual: upload a logo to Supabase, verify it appears in app
