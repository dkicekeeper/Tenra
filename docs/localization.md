# Localization

How Tenra is localized and the rules for changing a string or adding a language. App Store
metadata (titles, keywords, descriptions, What's New) lives in App Store Connect, read with
`appstore/asc.py` ([asc.md](asc.md)); ASO work is tracked in [promotion-plan.md](promotion-plan.md).

History: the July 2026 localization plan, with the market and keyword research per language,
is in [archive/localization-2026-07/](archive/localization-2026-07/).

## Locales

- **In the app: 11.** en (development language and fallback), ru, de, es, fr, tr, pt-BR, it, uk,
  ja, ko. Each `Tenra/<locale>.lproj/` holds `Localizable.strings`, `Localizable.stringsdict`
  (plurals), `InfoPlist.strings` (permission prompts) and `AppShortcuts.strings` (Siri phrases).
- **On the App Store: 13 storefront locales**: de-DE, en-US, es-ES, es-MX, fr-CA, fr-FR, it, ja,
  ko, pt-BR, ru, tr, uk. The app's es and fr cover both of their storefronts.
- **Features per language.** Voice input (`VoiceInputParser`, `VoiceInputSegmenter`) and CSV type
  values (`CSVColumnMapping`) understand the nine languages written with spaces. ja and ko get the
  UI, dates and currencies in voice input; parsing amounts and categories from ja/ko speech is
  deferred (it needs word segmentation; notes in the archive). Statement and receipt import is
  language-independent (Vision documents, [domains/import.md](domains/import.md)).

## Changing or adding a string

- **Every locale, in the same commit.** A key missing from a locale shows the raw key there.
  Parity check per locale:
  `diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings) <(grep -oE '^"[^"]+"' Tenra/<L>.lproj/Localizable.strings)`
  (an order difference is fine; a missing key is not).
- **Write with Python** (`io.open(path, encoding="utf-8")`), never `perl -CSD`, which re-encodes the
  script's UTF-8 into mojibake. Grep one non-Latin locale (ru, ja) afterwards.
- **Format specifiers:** a translation that reorders arguments uses positional ones
  (`%1$@ … %2$lld`); never mix positional and plain in one string. A bare `%` in a string read
  with `String(localized:)` and no arguments stays single.
- **No em dashes** in any user-facing text: comma, colon, period, or two sentences.
- **Quotes:** escape straight quotes (`\"`) or use the language's own (« », „ “, 「 」).
- **Tone** (set by the existing translations; follow it, don't choose again): de *Sie*, fr *vous*,
  ru and uk *вы*, es, it, pt-BR and tr informal, ja and ko polite (です/ます, 해요). "Tenra Pro" is
  never translated.
- **Plurals** go in `.stringsdict`: ru and uk one/few/many/other; ja and ko other only; the rest
  one/other (fr and pt-BR use "one" for 0 and 1.x too, check the wording). Any string with a
  count next to a noun ("%lld accounts") is a plural, in every locale (tr: one = other), and the
  key lives only in `.stringsdict`. Format it with
  `String(format: NSLocalizedString("key", comment: ...), n)`, as the Finances cards do;
  `PluralCountStringsTests` pins the forms.

## Permission prompts

Every locale has `InfoPlist.strings` with the five usage strings (`NSCameraUsageDescription`,
`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`,
`NSDocumentPickerUsageDescription`, `NSFaceIDUsageDescription`); `Info.plist` holds the English
fallback. A new `NS…UsageDescription` key goes into all 11 files.

## Adding a language

1. Register it in **both** `knownRegions` (`project.pbxproj`) and `CFBundleLocalizations`
   (`Info.plist`).
2. Translate `Localizable.strings`, `Localizable.stringsdict`, `InfoPlist.strings`,
   `AppShortcuts.strings`.
3. Voice: expense and income verbs (`expenseKeywords` / `incomeKeywords`), relative dates in
   `parseDate`, category keywords, `VoiceInputSegmenter` conjunctions, brand aliases in
   `ServiceLogo`. ⚠️ `VoiceInputParser.categoryMap` and `CSVColumnMapping.typeMappings` are flat
   dictionary literals: a key another language already uses (`benzin` de+tr, `бензин` ru+uk)
   crashes at runtime. Grep for duplicates and leave the collision out.
4. CSV: type values in `CSVColumnMapping` (`расход/доход/перевод` → expense/income/transfer).
5. App Store: metadata in App Store Connect, screenshots with `scripts/capture_screenshots.sh`
   (demo data, `-ScreenshotDemo`, never on the personal device) and the captions in
   `scripts/screenshot_captions.json`, prices per storefront, the RevenueCat paywall texts.
