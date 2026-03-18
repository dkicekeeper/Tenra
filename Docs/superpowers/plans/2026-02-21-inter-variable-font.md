# Inter Variable Font Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 18 static Overpass `.ttf` files with 2 Inter variable font files (`Inter[opsz,wght].ttf` + `Inter-Italic[opsz,wght].ttf`), update `AppTypography` to use `.weight()` modifiers, and wire up the new files in the Xcode project.

**Architecture:** Two-file variable font (weight axis 100–900 + optical size axis 14–32 pt) replaces 18 static files. `AppTypography` enum gains an `AppInterFont` namespace with two family-name constants; each font level gains a `.weight()` modifier. All 77+ view files remain untouched — they use the public `AppTypography.*` API.

**Tech Stack:** SwiftUI `Font.custom(_:size:relativeTo:).weight(_:)`, Python script to patch `project.pbxproj`, direct edits to `Info.plist` and `AppTheme.swift`.

---

## Prerequisites (Manual — user must complete before running tasks)

1. Go to https://fonts.google.com/specimen/Inter and click **Download family**.
2. Unzip the archive. Inside, locate the two variable font files (they are in the **root** of the zip, NOT in `static/`):
   - `Inter[opsz,wght].ttf`
   - `Inter-Italic[opsz,wght].ttf`
3. Copy both files into `Fonts/` at the repo root (same folder that currently holds `Overpass-*.ttf`).
4. Verify they are present:
   ```
   ls Fonts/Inter*.ttf
   # Expected: Fonts/Inter[opsz,wght].ttf   Fonts/Inter-Italic[opsz,wght].ttf
   ```

---

## Task 1: Write the project.pbxproj migration script

**Files:**
- Create: `Scripts/migrate_fonts.py`

**Step 1: Create the script**

```python
#!/usr/bin/env python3
"""
Migrate project.pbxproj: replace 18 Overpass static fonts with 2 Inter variable fonts.
Run from repo root: python3 Scripts/migrate_fonts.py
"""

INTER_REF          = "AA0001002F477D4A0010A953"
INTER_ITALIC_REF   = "AA0002002F477D4A0010A953"
INTER_BUILD        = "AA0003002F477D4A0010A953"
INTER_ITALIC_BUILD = "AA0004002F477D4A0010A953"
FONTS_GROUP_UUID   = "D69F99D72F477D4A0010A953"
RESOURCES_UUID     = "D62A098F2F0D7B0D004AF1FA"
PBXPROJ            = "AIFinanceManager.xcodeproj/project.pbxproj"

with open(PBXPROJ) as f:
    content = f.read()

# ── 1. Remove ALL Overpass lines ──────────────────────────────────────────────
content = "".join(
    line for line in content.splitlines(keepends=True)
    if "Overpass" not in line
)

# ── 2. Insert Inter PBXBuildFile entries (right after section marker) ─────────
inter_build = (
    f'\t\t{INTER_BUILD} /* Inter[opsz,wght].ttf in Resources */ = '
    f'{{isa = PBXBuildFile; fileRef = {INTER_REF} /* Inter[opsz,wght].ttf */; }};\n'
    f'\t\t{INTER_ITALIC_BUILD} /* Inter-Italic[opsz,wght].ttf in Resources */ = '
    f'{{isa = PBXBuildFile; fileRef = {INTER_ITALIC_REF} /* Inter-Italic[opsz,wght].ttf */; }};\n'
)
content = content.replace(
    "/* Begin PBXBuildFile section */\n",
    "/* Begin PBXBuildFile section */\n" + inter_build,
    1,
)

# ── 3. Insert Inter PBXFileReference entries ──────────────────────────────────
inter_refs = (
    f'\t\t{INTER_REF} /* Inter[opsz,wght].ttf */ = '
    f'{{isa = PBXFileReference; lastKnownFileType = file; path = "Inter[opsz,wght].ttf"; sourceTree = "<group>"; }};\n'
    f'\t\t{INTER_ITALIC_REF} /* Inter-Italic[opsz,wght].ttf */ = '
    f'{{isa = PBXFileReference; lastKnownFileType = file; path = "Inter-Italic[opsz,wght].ttf"; sourceTree = "<group>"; }};\n'
)
content = content.replace(
    "/* Begin PBXFileReference section */\n",
    "/* Begin PBXFileReference section */\n" + inter_refs,
    1,
)

# ── 4. Populate Fonts PBXGroup children (was empty after step 1) ──────────────
inter_children = (
    f'\t\t\t\t{INTER_REF} /* Inter[opsz,wght].ttf */,\n'
    f'\t\t\t\t{INTER_ITALIC_REF} /* Inter-Italic[opsz,wght].ttf */,\n'
)
content = content.replace(
    f'{FONTS_GROUP_UUID} /* Fonts */ = {{\n'
    '\t\t\tisa = PBXGroup;\n'
    '\t\t\tchildren = (\n'
    '\t\t\t);',
    f'{FONTS_GROUP_UUID} /* Fonts */ = {{\n'
    '\t\t\tisa = PBXGroup;\n'
    '\t\t\tchildren = (\n'
    + inter_children +
    '\t\t\t);',
    1,
)

# ── 5. Populate main-target Resources build phase ─────────────────────────────
inter_resources = (
    f'\t\t\t\t{INTER_BUILD} /* Inter[opsz,wght].ttf in Resources */,\n'
    f'\t\t\t\t{INTER_ITALIC_BUILD} /* Inter-Italic[opsz,wght].ttf in Resources */,\n'
)
content = content.replace(
    f'{RESOURCES_UUID} /* Resources */ = {{\n'
    '\t\t\tisa = PBXResourcesBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    '\t\t\t);',
    f'{RESOURCES_UUID} /* Resources */ = {{\n'
    '\t\t\tisa = PBXResourcesBuildPhase;\n'
    '\t\t\tbuildActionMask = 2147483647;\n'
    '\t\t\tfiles = (\n'
    + inter_resources +
    '\t\t\t);',
    1,
)

with open(PBXPROJ, "w") as f:
    f.write(content)

remaining = content.count("Overpass")
print(f"✅  project.pbxproj updated")
print(f"    Remaining 'Overpass' references: {remaining}  (expected 0)")
print(f"    'Inter' references: {content.count('Inter')}")
assert remaining == 0, f"FAIL: {remaining} Overpass references remain"
```

**Step 2: Commit the script (before running it)**

```bash
git add Scripts/migrate_fonts.py
git commit -m "chore(fonts): add project.pbxproj migration script for Inter variable font"
```

---

## Task 2: Run the migration script

**Files:**
- Modify: `AIFinanceManager.xcodeproj/project.pbxproj` (via script)

**Step 1: Run the script**

```bash
python3 Scripts/migrate_fonts.py
```

Expected output:
```
✅  project.pbxproj updated
    Remaining 'Overpass' references: 0  (expected 0)
    'Inter' references: 8
```

If the script prints a non-zero Overpass count or raises an AssertionError, check that:
- The UUIDs `D69F99D72F477D4A0010A953` (Fonts group) and `D62A098F2F0D7B0D004AF1FA` (Resources) are still correct — verify with `grep -n "Fonts \*/ = {" AIFinanceManager.xcodeproj/project.pbxproj`
- The exact indentation strings in steps 4 and 5 match the live file — print the affected block and compare

**Step 2: Spot-check the result**

```bash
grep "Inter" AIFinanceManager.xcodeproj/project.pbxproj
```

Expected: 8 lines — 2 PBXBuildFile, 2 PBXFileReference, 2 PBXGroup children, 2 PBXResourcesBuildPhase.

```bash
grep "Overpass" AIFinanceManager.xcodeproj/project.pbxproj
```

Expected: no output.

**Step 3: Commit**

```bash
git add AIFinanceManager.xcodeproj/project.pbxproj
git commit -m "chore(fonts): migrate project.pbxproj from 18 Overpass static to 2 Inter variable"
```

---

## Task 3: Update Info.plist — register Inter fonts

**Files:**
- Modify: `AIFinanceManager/Info.plist` (lines 47–53)

**Step 1: Replace UIAppFonts array**

Current content (lines 47–53):
```xml
	<key>UIAppFonts</key>
	<array>
		<string>Overpass-Regular.ttf</string>
		<string>Overpass-Medium.ttf</string>
		<string>Overpass-SemiBold.ttf</string>
		<string>Overpass-Bold.ttf</string>
	</array>
```

Replace with:
```xml
	<key>UIAppFonts</key>
	<array>
		<string>Inter[opsz,wght].ttf</string>
		<string>Inter-Italic[opsz,wght].ttf</string>
	</array>
```

**Step 2: Verify no Overpass remains in Info.plist**

```bash
grep "Overpass" AIFinanceManager/Info.plist
```

Expected: no output.

**Step 3: Commit**

```bash
git add AIFinanceManager/Info.plist
git commit -m "chore(fonts): update UIAppFonts — register Inter variable font files"
```

---

## Task 4: Update AppTheme.swift — replace AppOverpassFont with AppInterFont

**Files:**
- Modify: `AIFinanceManager/Utils/AppTheme.swift` (lines 150–221)

**Step 1: Replace the private font namespace (lines 150–159)**

Current:
```swift
// MARK: - Overpass Font Helper

/// Centralizes Overpass font name constants (PostScript names as registered in UIAppFonts).
/// Verify with: UIFont.fontNames(forFamilyName: "Overpass")
private enum AppOverpassFont {
    static let regular  = "Overpass-Regular"
    static let medium   = "Overpass-Medium"
    static let semibold = "Overpass-SemiBold"
    static let bold     = "Overpass-Bold"
}
```

Replace with:
```swift
// MARK: - Inter Font Helper

/// Centralizes Inter variable font family names (as registered in UIAppFonts).
/// Weight and optical-size axes are set via .weight() modifier and pointSize automatically.
/// Verify with: UIFont.fontNames(forFamilyName: "Inter")
private enum AppInterFont {
    static let family       = "Inter"
    static let familyItalic = "Inter-Italic"
}
```

**Step 2: Replace the AppTypography enum body (lines 161–221)**

Current:
```swift
// MARK: - Typography System

/// Консистентная система типографики с уровнями.
/// Использует Overpass (Google Fonts, SIL OFL) с Dynamic Type через Font.custom(_:size:relativeTo:).
enum AppTypography {
    // MARK: Headers

    /// H1 - Screen titles (34pt bold, scales with largeTitle)
    static let h1 = Font.custom(AppOverpassFont.bold, size: 34, relativeTo: .largeTitle)

    /// H2 - Major section titles (28pt semibold, scales with title)
    static let h2 = Font.custom(AppOverpassFont.semibold, size: 28, relativeTo: .title)

    /// H3 - Card headers, modal titles (22pt semibold, scales with title2)
    static let h3 = Font.custom(AppOverpassFont.semibold, size: 24, relativeTo: .title2)

    /// H4 - Row titles, list item headers (20pt semibold, scales with title3)
    static let h4 = Font.custom(AppOverpassFont.semibold, size: 20, relativeTo: .title3)

    // MARK: Body Text

    /// Body Large - Emphasized body text (17pt medium, scales with body)
    static let bodyLarge = Font.custom(AppOverpassFont.medium, size: 18, relativeTo: .body)

    /// Body - Default text (17pt regular, scales with body)
    static let body = Font.custom(AppOverpassFont.regular, size: 18, relativeTo: .body)

    /// Body Small - Secondary text (15pt regular, scales with subheadline)
    static let bodySmall = Font.custom(AppOverpassFont.regular, size: 16, relativeTo: .subheadline)

    // MARK: Captions

    /// Caption - Helper text, timestamps, metadata (12pt regular, scales with caption)
    static let caption = Font.custom(AppOverpassFont.regular, size: 14, relativeTo: .caption)

    /// Caption Emphasis - Important helper text (12pt medium, scales with caption)
    static let captionEmphasis = Font.custom(AppOverpassFont.medium, size: 14, relativeTo: .caption)

    /// Caption 2 - Very small text (11pt regular, scales with caption2)
    static let caption2 = Font.custom(AppOverpassFont.regular, size: 12, relativeTo: .caption2)

    // MARK: - Semantic Typography

    /// Screen titles (alias для h1)
    static let screenTitle = h1

    /// Section headers (alias для captionEmphasis)
    static let sectionHeader = captionEmphasis

    /// Primary body text (alias для body)
    static let bodyPrimary = body

    /// Secondary text (alias для bodySmall)
    static let bodySecondary = bodySmall

    /// Label text (15pt medium, scales with subheadline)
    static let label = Font.custom(AppOverpassFont.medium, size: 16, relativeTo: .subheadline)

    /// Amount text (17pt semibold, scales with body)
    static let amount = Font.custom(AppOverpassFont.semibold, size: 18, relativeTo: .body)
}
```

Replace with:
```swift
// MARK: - Typography System

/// Консистентная система типографики с уровнями.
/// Использует Inter variable font (Google Fonts, SIL OFL) с Dynamic Type.
/// Ось opsz (optical size) применяется автоматически — iOS передаёт pointSize как значение opsz.
/// Веса задаются через .weight() модификатор, который маппируется на ось wght (100–900).
enum AppTypography {
    // MARK: Headers

    /// H1 - Screen titles (34pt bold, scales with largeTitle)
    static let h1 = Font.custom(AppInterFont.family, size: 34, relativeTo: .largeTitle).weight(.bold)

    /// H2 - Major section titles (28pt semibold, scales with title)
    static let h2 = Font.custom(AppInterFont.family, size: 28, relativeTo: .title).weight(.semibold)

    /// H3 - Card headers, modal titles (24pt semibold, scales with title2)
    static let h3 = Font.custom(AppInterFont.family, size: 24, relativeTo: .title2).weight(.semibold)

    /// H4 - Row titles, list item headers (20pt semibold, scales with title3)
    static let h4 = Font.custom(AppInterFont.family, size: 20, relativeTo: .title3).weight(.semibold)

    // MARK: Body Text

    /// Body Large - Emphasized body text (18pt medium, scales with body)
    static let bodyLarge = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.medium)

    /// Body - Default text (18pt regular, scales with body)
    static let body = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.regular)

    /// Body Small - Secondary text (16pt regular, scales with subheadline)
    static let bodySmall = Font.custom(AppInterFont.family, size: 16, relativeTo: .subheadline).weight(.regular)

    // MARK: Captions

    /// Caption - Helper text, timestamps, metadata (14pt regular, scales with caption)
    static let caption = Font.custom(AppInterFont.family, size: 14, relativeTo: .caption).weight(.regular)

    /// Caption Emphasis - Important helper text (14pt medium, scales with caption)
    static let captionEmphasis = Font.custom(AppInterFont.family, size: 14, relativeTo: .caption).weight(.medium)

    /// Caption 2 - Very small text (12pt regular, scales with caption2)
    static let caption2 = Font.custom(AppInterFont.family, size: 12, relativeTo: .caption2).weight(.regular)

    // MARK: - Semantic Typography

    /// Screen titles (alias для h1)
    static let screenTitle = h1

    /// Section headers (alias для captionEmphasis)
    static let sectionHeader = captionEmphasis

    /// Primary body text (alias для body)
    static let bodyPrimary = body

    /// Secondary text (alias для bodySmall)
    static let bodySecondary = bodySmall

    /// Label text (16pt medium, scales with subheadline)
    static let label = Font.custom(AppInterFont.family, size: 16, relativeTo: .subheadline).weight(.medium)

    /// Amount text (18pt semibold, scales with body)
    static let amount = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.semibold)
}
```

**Step 3: Verify no AppOverpassFont references remain**

```bash
grep -rn "AppOverpassFont\|Overpass" AIFinanceManager/
```

Expected: no output.

**Step 4: Commit**

```bash
git add AIFinanceManager/Utils/AppTheme.swift
git commit -m "feat(typography): migrate AppTypography from Overpass static to Inter variable font"
```

---

## Task 5: Build verification

**Step 1: Build the project**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | tail -20
```

Expected output ends with:
```
** BUILD SUCCEEDED **
```

**If BUILD FAILED:**

Common causes:
1. `Inter[opsz,wght].ttf` not in `Fonts/` directory → copy font files per Prerequisites
2. `project.pbxproj` migration script didn't run or had a mismatch → re-check Task 2
3. Typo in font family name → verify with:
   ```swift
   // Add temporarily in AppCoordinator.initialize() or similar
   print(UIFont.fontNames(forFamilyName: "Inter"))
   // Expected: ["Inter-Italic", "Inter"]
   ```
4. Info.plist has wrong filename → verify exact filename matches `ls Fonts/Inter*.ttf`

**Step 2: Verify font loads at runtime (optional quick check)**

Add this one-liner temporarily to `AppCoordinator.initialize()` (remove before final commit):
```swift
assert(!UIFont.fontNames(forFamilyName: "Inter").isEmpty, "Inter variable font not loaded")
```

---

## Task 6: Delete Overpass font files and final commit

**Step 1: Delete Overpass files from disk**

```bash
rm Fonts/Overpass-*.ttf
ls Fonts/
```

Expected: only `Inter[opsz,wght].ttf` and `Inter-Italic[opsz,wght].ttf` remain.

**Step 2: Verify bundle size improvement**

```bash
du -sh Fonts/
# Expected: ~1.0M (vs ~3.0M before)
```

**Step 3: Remove migration script (no longer needed)**

```bash
rm Scripts/migrate_fonts.py
```

If `Scripts/` is now empty, remove it too:
```bash
rmdir Scripts/ 2>/dev/null || true
```

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(fonts): replace Overpass (18 static) with Inter variable font (2 files, -68% size)"
```

---

## Summary

| Step | Action | Files changed |
|------|--------|---------------|
| Task 1 | Write migration script | `Scripts/migrate_fonts.py` |
| Task 2 | Patch project.pbxproj | `AIFinanceManager.xcodeproj/project.pbxproj` |
| Task 3 | Register fonts in Info.plist | `AIFinanceManager/Info.plist` |
| Task 4 | Update AppTypography | `AIFinanceManager/Utils/AppTheme.swift` |
| Task 5 | Build verification | — |
| Task 6 | Remove Overpass files | `Fonts/Overpass-*.ttf` (deleted) |

**View files changed:** 0 (all 77+ consumers use `AppTypography.*` public API unchanged)
