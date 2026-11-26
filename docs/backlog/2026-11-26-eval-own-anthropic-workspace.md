---
status: idea
type: chore
priority: 2
created: 2026-11-26
updated: 2026-11-26
---
# The eval's own Anthropic workspace

**The eval's own Anthropic workspace** (the owner): the `eval` and `eval-valuation` jobs of
`assistant.yml` read `ANTHROPIC_EVAL_API_KEY` since 2026-11-06 and have run on it since 12.11
(the deploy keeps `ANTHROPIC_API_KEY`). Left: confirm the "Tenra eval" workspace has its own
spend limit (about $15 a month covers two release evals on Haiku and Sonnet).

Found by the release audit of 2026-10-15 (details and file references:
[archive/release-audit-1.6-2026-10-15.md](../archive/release-audit-1.6-2026-10-15.md)):
