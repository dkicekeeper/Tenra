---
status: active
decided: 2026-10-12
by: owner
---
# No behavioural analytics SDK

**No behavioural analytics SDK** (2026-10-12): crashes and usage come from App Analytics,
Xcode Organizer, TestFlight and on-device Diagnostics; the App Privacy label lists what Ten
sends (since 1.6). The exceptions are on Tenra's own server, with no identifier (2026-11-25):
Ten's answers counted by labels, never words ([domains/assistant.md](../domains/assistant.md) §8
"Turn statistics"), and the app's own steps and return days from 1.10
([domains/analytics.md](../domains/analytics.md)), both off with one switch in Settings › Privacy;
the label's Usage Data › Product Interaction for Analytics covers them.
Screen-level analytics (TelemetryDeck or Aptabase) only once traffic makes it meaningful.
