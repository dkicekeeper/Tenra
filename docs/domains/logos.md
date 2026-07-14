# Logos Domain

Logo provider chain, `ServiceLogoRegistry`, and brand icon resolution.

## Provider Chain

```
JsDelivrLogoProvider → LogoDevProvider → GoogleFaviconProvider → LettermarkProvider
```

`LogoProviderChain.fetch()` returns `LogoProviderResult` with `providerName` + `shouldCacheToDisk`.

## JsDelivrLogoProvider (Primary)

Auto-indexes the [dkicekeeper/tenra-assets](https://github.com/dkicekeeper/tenra-assets) GitHub repo via the jsDelivr packages API:

```
https://data.jsdelivr.com/v1/packages/gh/dkicekeeper/tenra-assets@main?structure=flat
```

- Fuzzy-matches normalized filenames (strips spaces/underscores/hyphens/dots + common affixes like "bank")
- Index cached to disk (`jsdelivr_logo_index.json`), refreshed daily
- Empty index retries every 60s
- Files served from `https://cdn.jsdelivr.net/gh/dkicekeeper/tenra-assets@main/logos/<file>`

### Repo requirements

- `dkicekeeper/tenra-assets` must stay **public** (jsDelivr serves only public GH repos)
- To force-refresh after edits: use jsDelivr purge API
- For full version pinning: swap `@main` for a tag (`@v1`) in `JsDelivrLogoProvider.packageAPI` + `cdnBase`
- **No auth/keys required** — public CDN, no Info.plist entries

## LogoDevProvider

- Uses logo.dev API
- 5s timeout
- Checks `LogoDevConfig.isAvailable` internally

## GoogleFaviconProvider

- Uses Google Favicon API (`sz=128`)
- Rejects responses <1KB or images ≤16x16

## LettermarkProvider

- Generates letter icons with djb2 deterministic colors
- ⚠️ **Never cached to disk** (so real logos can override later)

## Disk Cache

`LogoDiskCache` has `cacheVersion` — bump it to invalidate stale cache on next launch.

## DominantColorExtractor

`Services/Utilities/DominantColorExtractor.swift` — derives a brand-accent colour from a logo (`accentColor(forBrand:)`) for the entity-detail hero glow (`.heroAccentGlow`, see design-system.md). Histogram over a 24×24 downsample (off-MainActor), filters transparent/near-white/near-black/gray pixels, normalizes the winner via HSB. Returns `nil` for logos with no saturated pixels — callers keep their fallback tint. Results cached in-memory per resolved domain (logos are immutable per domain; `cacheVersion` bump is the escape hatch). Lettermark fallbacks yield their deterministic djb2 background colour — stable, but not a real brand colour.

## ServiceLogoRegistry

`nonisolated enum`:
- `allServices` (170+)
- `domainMap`
- `aliasMap`
- `resolveDomain(from:)`
- `search(query:)`

### ServiceLogoEntry

Fields: `domain`, `displayName`, `category`, `aliases`.

⚠️ **No `logoFilename`, no `bankLogo`** — these were removed.

### ServiceCategory

Cases: `.banks`, `.localServices`, `.telecom`, `.cis` + original 7 categories.

## IconStyle Rename

⚠️ **Old → New**:
- `.bankLogo()` → `.roundedLogo()`
- `.bankLogoLarge()` → `.roundedLogoLarge()`

## BankLogo Enum

⚠️ **BankLogo enum deleted** — all logos go through provider chain via `.brandService(domain)`.
