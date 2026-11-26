---
status: active
decided: 2026-11-10
by: owner
---
# Siri intents do not deduplicate

**Siri intents do not deduplicate** (2026-11-10): repeating a phrase can log the same
transaction twice, and the confirmation snippet is the guard. Wallet payments and bank
notifications keep their own ([domains/intents.md](../domains/intents.md) §6.1).
