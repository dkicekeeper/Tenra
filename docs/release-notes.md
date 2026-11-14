# Tenra, the next version: What's New and the checklist

1.8.3 is in the store since 2026-11-14 (build 90; its notes, App Review notes and checklist:
[archive/release-notes-1.8.3.md](archive/release-notes-1.8.3.md)). The next version is not
chosen yet: 1.9 is kept for the update the featuring nomination promises in the last week of
December ([plan-growth.md](plan-growth.md) stage 4; build by 22.12, out 26-29.12).

When the blocks are written: one `## <locale>` heading per storefront (en-US, ru, en-GB, de-DE,
es-ES, es-MX, fr-FR, fr-CA, tr, pt-BR, it, uk, ja, ko), which `prepare-version` (Actions → App
Store Connect, [asc.md](asc.md)) pastes into App Store Connect; en-GB (search in Kazakhstan)
carries ru's text. No em dashes (user rule). `prepare-version` refuses notes whose title names
another version.

## In this version

Nothing yet.

## On the phone, left from the versions already in the store

Not marked done before 1.8.3 went out; the store build is the one to check:

1. **1.8.3** (build 90): the 18 checks of
   [archive/release-notes-1.8.3.md](archive/release-notes-1.8.3.md) «On the phone before this
   version goes out» (feedback through Ten reaching Telegram, Ten's forms and drafts, Ten's
   home, the gates' own headlines).
2. **1.8.2 and 1.8.1**: the list «On the phone, left from the versions already in the store» in
   the same file (the onboarding trial offer, bank pushes merging into a subscription charge or a
   transfer, the evening push, the actions' names).

## Submission checklist

1. **CI green**, then a TestFlight build.
2. **The phone checks above.**
3. **What's New** in this file, then `prepare-version --version <V> --build <N>`.
4. **App Review notes**, in English, in a block here, set by `asc.py review-notes --version <V> --apply`
   (start from the 1.8.3 block in the archive).
5. **One submission**: `asc.py prepare-review --version <V>`; the founder sends it, or
   `--submit` on the founder's word.
