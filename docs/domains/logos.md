# Logos Domain

Logo provider chain (`Services/Core/`), `ServiceLogoRegistry`, and brand icon resolution. `Icon`, `IconSource` (`.brandService(domain)`) and `IconStyle` are DesignKit's (`DesignSupport`); DesignKit asks `LogoService` for the image through `DesignKitLogoLoader.loader`, set in `DesignKitBridge.swift`, which also adds `IconSource.brandDomain`.

## Provider Chain

```
JsDelivrLogoProvider → LogoDevNameProvider → LogoDevProvider → GoogleFaviconProvider → LettermarkProvider
```

`LogoDevNameProvider` answers only keys starting with `name:` (a merchant's logo found by its
name, below); the others skip those keys.

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

## Merchant logos

A transaction row shows its merchant's logo instead of the category icon (`TransactionCard`,
after a subscription's and a loan's logo; the category stays the row's title), behind Settings →
General → "Merchant logos" (`MerchantLogoStore.enabledKey`, on by default). Plan:
[plan-auto-capture.md](../plan-auto-capture.md) §5.

- `MerchantName.displayName` (`Services/Categories/`): the clean name from a bank's or Wallet's
  text ("MAGNUM CASH&CARRY 123" → "Magnum Cash&Carry"): store numbers, processor prefixes
  (SQ \*, PAYPAL \*), legal forms (ТОО, ИП, LLP) and a trailing city or country go; text in
  capitals is re-cased, acronyms of up to three letters and domains excepted. Display and lookup
  only: the stored description is never rewritten.
- `MerchantLogoResolver.lookUp`, most private first: `ServiceLogoRegistry` by the clean name or
  its first words → the tenra-assets index matched on device
  (`JsDelivrLogoProvider.indexName(forMerchant:)`) → logo.dev by name
  (`img.logo.dev/name/{name}?fallback=404`, the image saved to `LogoDiskCache` under
  `name:<clean name>`; owner's decision 2026-10-19; never for a sole proprietor, ИП / IP, whose
  name is a person's: `MerchantName.isSoleProprietor`). No lettermark and no Google favicon: a
  merchant without a real logo keeps its category icon.
- `MerchantLogoStore`: normalized merchant → `.found(key)` or `.missing` with the date; "missing"
  is looked up again after 30 days. `iconSource(forDescription:)` memoizes per description and
  reads `version`, so rows re-render when a logo is found.
- Lookups run only in the app, when it comes to the front (`MainTabView`), never in an intent:
  - the merchants Apple Pay payments came from (`MerchantCategoryMemory`, `WalletCaptureStore`):
    all three sources, at most 12 per pass. Apple Pay only pays shops;
  - the history's frequent merchants (3+ expense or income visits, counted off the main actor,
    `frequentMerchants`): the registry and tenra-assets only, at most 50 per pass, every 12 hours.
    A statement's rows include transfers to people, whose names never leave the device. A
    merchant checked on device only is asked online once it turns up in an Apple Pay payment
    (`MerchantLogoStore.Entry.lookedUpOnline`).

  Any transaction whose description is the same merchant gets the logo, whatever recorded it.
- Pinned by `MerchantLogoTests`.
