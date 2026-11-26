---
status: idea
type: chore
priority: 2
created: 2026-11-26
updated: 2026-11-26
---
# Assistant performance

**Assistant performance:** full-resolution photo decode on the main thread; each streamed piece
re-parses the reply and re-renders the chat; allowance Keychain calls on the main thread;
FastPath runs the voice parser on questions; `forecast_balance` series O(days × occurrences).
