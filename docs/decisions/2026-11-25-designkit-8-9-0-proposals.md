---
status: active
decided: 2026-11-25
by: owner
---
# DesignKit 8.9.0's proposals that Tenra does not take

**DesignKit 8.9.0's proposals that Tenra does not take** (2026-11-25, DesignKit's
`docs/adoption.md`; `SearchablePicker`, `ConversationDivider` and `AccessibilityAnnouncer` it
took, [design-system.md](../design-system.md) §4): `InfoTip`, since every figure it was proposed
for explains itself on the screen (Financial Health's weighting card and each part's
explanation, "How it's calculated" on the forecast and "For today", By day's footnote) and every
figure on Analytics is a link to that screen, where an ⓘ would be a button inside a button;
`MessageBubble(markdown:)` for Ten's replies, which stay on the page between their cards (their
Markdown is read by DesignKit's `ArticleBody.Block.parse`), and `time:` / `status:`, as nothing
is delivered to a person and the day lines say when; a `ConversationDivider` for "Ten changed
the budget", as the draft card itself says Saved, with Undo; `SearchablePicker` for a
transaction's category (the form's chip row; a category needs its icon and colour) and for
link payments (transactions, with their amounts and days).
