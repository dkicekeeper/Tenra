# Logos Domain

Logo provider chain (`Services/Core/`), `ServiceLogoRegistry`, and brand icon resolution. `Icon`, `IconSource` (`.brandService(domain)`) and `IconStyle` are DesignKit's (`DesignSupport`); DesignKit asks `LogoService` for the image through `DesignKitLogoLoader.loader`, set in `DesignKitBridge.swift`, which also adds `IconSource.brandDomain`.

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
- **No auth/keys required**: public CDN

## LogoDevProvider

- Uses logo.dev API
- 5s timeout
- Needs `LOGO_DEV_PUBLIC_KEY` in Info.plist: without it `LogoDevConfig.logoURL(for:)` returns nil and the provider is skipped

## GoogleFaviconProvider

- Uses Google Favicon API (`sz=128`)
- Rejects responses <1KB or images ≤16x16

## LettermarkProvider

- Generates letter icons with djb2 deterministic colors
- ⚠️ **Never cached to disk** (so real logos can override later)

## Disk Cache

`LogoDiskCache` has `cacheVersion` — bump it to invalidate stale cache on next launch.

⚠️ **The cache is `nonisolated`, and `load` / `exists` are `async` on purpose**: under the
project's MainActor default a miss would read and decode a PNG on the main thread, N brands back
to back on the first render of an account or subscription list. `save` is fire-and-forget (the
caller already has the image) and encodes and writes the PNG in a detached task. Keep new file
work in this class `async`, and do not make it MainActor to "simplify" a call site.

Every provider in the chain is already `nonisolated`, so their network and disk work never
touched the main actor. `LogoService` stays `@MainActor` — between awaits it only does NSCache
lookups and string normalization.

## DominantColorExtractor

DesignKit's `DominantColorExtractor` (`DesignSupport`, fed by `DesignKitLogoLoader.loader` → `LogoService`, wired in `DesignKitBridge`) — derives a brand-accent colour from a logo (`accentColor(forBrand:)`) for the entity-detail hero glow (`.heroAccentGlow`, DesignKit's `docs/motion.md`) and the insight detail screens (`InsightDetailView`, `InsightDeepDiveView`). Histogram over a 24×24 downsample (off-MainActor), filters transparent/near-white/near-black/gray pixels, normalizes the winner via HSB. Returns `nil` for logos with no saturated pixels — callers keep their fallback tint. Results are cached in an in-memory `NSCache` keyed by the lowercased brand name. Lettermark fallbacks yield their deterministic djb2 background colour — stable, but not a real brand colour.

## ServiceLogoRegistry

`nonisolated enum`:
- `allServices` (147 entries)
- `domainMap`
- `aliasMap`
- `resolveDomain(from:)`
- `search(query:)`

### ServiceLogoEntry

Fields: `domain`, `displayName`, `category`, `aliases`.

### ServiceCategory

Cases: `.banks`, `.streaming`, `.productivity`, `.social`, `.fitness`, `.gaming`, `.devTools`, `.services`, `.localServices`, `.telecom`, `.cis`.

Bank and brand logos render through the provider chain with `IconSource.brandService(domain)`; `IconStyle.roundedLogo()` / `.roundedLogoLarge()` are the logo styles (a circle in the logo's own colours).
