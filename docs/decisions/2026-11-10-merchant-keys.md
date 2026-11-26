---
status: active
decided: 2026-11-10
by: owner
---
# Merchant keys stay as they are

**Merchant keys stay as they are** (2026-11-10): every store keys on
`CategorySuggestionService.normalizedMerchant`, so Wallet's "MAGNUM CASH&CARRY 123" and a
statement's "ТОО MAGNUM CASH&CARRY ALMATY KZ" can be two merchants; no migration to the clean
name. "Combine points" on the merchant's screen (`MerchantGroupStore`) merges them by hand for
the screen and the top merchant.
