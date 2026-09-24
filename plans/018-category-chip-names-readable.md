# Plan 018: Category names in the category carousel are readable (no "Каф…" truncation)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat a57d5fe4..HEAD -- Tenra/Views/Components/Input/CategorySelectorView.swift Tenra/Views/Components/Cards/CategoryChip.swift`

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (visual only)
- **Depends on**: none
- **Category**: layout
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

`CategorySelectorView` (used on the add/edit transaction screens, the voice confirmation, the
receipt confirmation and subscription editing) fixes each chip to 80 pt, and `CategoryChip`
renders the name in 18 pt semibold on one line with no scaling. That fits about 7 characters.
Most onboarding names are longer: ru "Кафе и рестораны", "Коммунальные", "Развлечения",
"Образование", "Путешествия"; uk "Комунальні послуги"; de "Dienstleistungen", "Lebensmittel";
es "Servicios públicos". They render as "Каф…", so users pick categories by icon alone.

## Current state

- `Tenra/Views/Components/Input/CategorySelectorView.swift:55-68`:
  ```swift
  ForEach(categories, id: \.self) { category in
      CategoryChip(...)
          .frame(width: 80)
          .id(category)
  }
  ```
- `Tenra/Views/Components/Cards/CategoryChip.swift:49-56`:
  ```swift
  VStack(spacing: AppSpacing.sm) {
      Text(category)
          .font(AppTypography.bodyEmphasis)
          .foregroundStyle(AppColors.textPrimary)
          .lineLimit(1)
      ZStack { ... icon / budget ring ... }
  ```
- `CategoryChip` is also used elsewhere; check call sites with `grep -rn "CategoryChip(" Tenra --include='*.swift'`
  so the change does not break other layouts.
- Typography tokens (`docs/design-system.md`): `bodyEmphasis` 18 semibold, `bodySmall` 16, `caption` 14.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |

## Scope

**In scope**: `CategoryChip.swift` (label styling), `CategorySelectorView.swift` (chip width) only.
**Out of scope**: `CategoryGridView` / `CategoryCardSelectorView` (different components); renaming categories.

## Git workflow

Commit directly on `main`; do not push. Message: `fix(layout): category chips show full names`.

## Steps

1. In `CategoryChip`, allow two lines and gentle scaling for the name:
   `.lineLimit(2)`, `.multilineTextAlignment(.center)`, `.minimumScaleFactor(0.8)`,
   `.fixedSize(horizontal: false, vertical: true)`, and use `AppTypography.caption` weight semibold
   (or `bodySmall`) if the chip remains visually balanced; keep `bodyEmphasis` only if two lines of it fit
   under the icon without clipping. Document the choice in a one-line comment.
2. In `CategorySelectorView`, widen the chip to 88 pt (keep a fixed width so the carousel's snapping stays even).
3. Make sure chips in a row align at the top (the icon row must line up when some names wrap to two lines):
   give the text a fixed two-line height (e.g. reserve it with `.frame(height:)` computed from the font) or align the
   VStack content to top.

**Verify**: Build → SUCCEEDED.

## Done criteria

- [ ] Build SUCCEEDED; only the two in-scope files changed; `plans/README.md` row 018 updated
- [ ] Human check below recorded in the report

## STOP conditions

- Another screen uses `CategoryChip` with its own width assumptions that the change breaks visibly (report with a screenshot).

## Maintenance notes

- Human check (Simulator is fine for layout): set the device language to Russian and German, open "add expense"
  and the voice confirmation: "Кафе и рестораны", "Коммунальные", "Dienstleistungen" are fully readable, icons aligned.
  Also check the largest non-accessibility Dynamic Type size.
