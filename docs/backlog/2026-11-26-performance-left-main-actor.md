---
status: idea
type: chore
priority: 2
created: 2026-11-26
updated: 2026-11-26
---
# Performance left on the main actor

**Performance left on the main actor:** `recalculateAll` for balances (one inverted O(N)
pass); History's CoreData refetch after each debounced (300 ms) search change (the fetched
results controller is bound to the view context).
