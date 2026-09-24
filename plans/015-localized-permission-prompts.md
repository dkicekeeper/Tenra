# Plan 015: System permission prompts (camera, microphone, speech, Face ID) appear in the user's language

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat a57d5fe4..HEAD -- Tenra/Info.plist Tenra/*.lproj`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs/l10n (user-facing strings)
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

The app is localized into 11 locales, but no locale has an `InfoPlist.strings`, so iOS shows the
raw `Info.plist` usage strings: English for camera, microphone, speech recognition, documents and
Face ID, to every user. The first time a Russian user taps Voice (a Pro feature) they get two English
system alerts. Also the notification string is Russian but sits on `NSUserNotificationUsageDescription`,
which iOS does not use (notification permission has no usage-string key), so it is dead.

## Current state

- `Tenra/Info.plist` usage strings (at planning time):
  - `NSCameraUsageDescription`: "Tenra uses the camera to scan paper receipts so you do not have to type them in by hand."
  - `NSDocumentPickerUsageDescription`: "This app needs access to your documents to analyze bank statements."
  - `NSFaceIDUsageDescription`: "Tenra uses Face ID to keep your finances locked when you turn on the app lock."
  - `NSMicrophoneUsageDescription`: "This app needs access to microphone to record voice for adding transactions."
  - `NSSpeechRecognitionUsageDescription`: "This app needs access to speech recognition to add transactions by voice."
  - `NSUserNotificationUsageDescription`: a Russian sentence (not an iOS key).
- `CFBundleLocalizations` in Info.plist lists all 11 locales; `CFBundleDevelopmentRegion` = en.
- Each `Tenra/<locale>.lproj/` currently holds `Localizable.strings`, `Localizable.stringsdict`, `AppShortcuts.strings`.
- The Xcode project uses file-system-synchronized groups: a new file inside an existing `.lproj`
  folder is picked up automatically (the existing `.strings` files there prove the folders are localized resources).
- CLAUDE.md: never use em dashes (—) in user-facing strings; write files with `python3` + `io.open(..., encoding="utf-8")`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tenra-dd015 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Bundle check | `ls /tmp/tenra-dd015/Build/Products/Debug-iphonesimulator/Tenra.app/ru.lproj/` | contains `InfoPlist.strings` |
| Lint | `for f in Tenra/*.lproj/InfoPlist.strings; do plutil -lint "$f"; done` | every file `OK` |

(Derived data goes to `/tmp` so nothing is written inside the repository.)

## Scope

**In scope**: `Tenra/<11 locales>.lproj/InfoPlist.strings` (create), `Tenra/Info.plist` (English base strings
reworded; remove `NSUserNotificationUsageDescription`).
**Out of scope**: any Swift code; App Store metadata.

## Git workflow

Commit directly on `main`; do not push. Message: `fix(l10n): localize system permission prompts`.

## Steps

### Step 1: Better English base strings in Info.plist

Replace the four "This app needs access..." strings with product-voice English (these also become `en.lproj` values):
- Microphone: "Tenra uses the microphone so you can add expenses by voice."
- Speech recognition: "Tenra turns what you say into transactions. Speech is processed by Apple."
- Documents: "Tenra reads the bank statements you choose to import them."
- Camera and Face ID: keep as is.
Remove the `NSUserNotificationUsageDescription` key and its string.

**Verify**: `plutil -lint Tenra/Info.plist` → OK.

### Step 2: InfoPlist.strings for all 11 locales

Create `Tenra/<L>.lproj/InfoPlist.strings` for en ru de es fr tr pt-BR it uk ja ko with the 5 keys
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`,
`NSDocumentPickerUsageDescription`, `NSFaceIDUsageDescription`. Format: `"NSCameraUsageDescription" = "...";`
Russian values:
- Camera: "Tenra использует камеру, чтобы сканировать бумажные чеки и не вводить их вручную."
- Microphone: "Tenra использует микрофон, чтобы вы могли добавлять расходы голосом."
- Speech: "Tenra превращает сказанное в операции. Речь обрабатывается Apple."
- Documents: "Tenra читает выбранные вами банковские выписки, чтобы импортировать их."
- Face ID: "Tenra использует Face ID, чтобы защитить ваши финансы, когда включена блокировка."
Translate the others naturally, matching each locale's existing formality (de "Sie", fr "vous", es/it "tú",
pt-BR "você"). Keep "Tenra", "Face ID", "Apple" untranslated. No em dashes.

**Verify**: Lint command → all OK; `grep -c '=' Tenra/*.lproj/InfoPlist.strings` → 5 per file;
`grep -n "Face ID" Tenra/ja.lproj/InfoPlist.strings Tenra/ru.lproj/InfoPlist.strings` shows readable text.

### Step 3: Bundle check

Build with the command above, then the bundle check → `InfoPlist.strings` present in `ru.lproj` (and `de.lproj`).

## Done criteria

- [ ] 11 `InfoPlist.strings` files, 5 keys each, all lint OK, no em dashes (`grep -n '—' Tenra/*.lproj/InfoPlist.strings` → none)
- [ ] Built app bundle contains them; `NSUserNotificationUsageDescription` gone from Info.plist
- [ ] `plans/README.md` row 015 updated

## STOP conditions

- The built bundle does not contain `InfoPlist.strings` (the synchronized group did not treat them as resources): report instead of editing `project.pbxproj`.

## Maintenance notes

- Device check: set the phone to Russian, delete and reinstall, tap Voice: the microphone and speech prompts are Russian.
- Any new `NS...UsageDescription` key must be added to all 11 `InfoPlist.strings`.
