# Plan 009: Weekly digest and insight signals actually reach users (provisional notification permission)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Services/Notifications Tenra/Views/Home/ContentView.swift`
> On any change, compare with the excerpts; a mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (provisional authorization shows no system prompt)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

Release 1.2's retention feature (weekly digest + insight signal pushes) is ON by default,
but both senders silently skip when notifications are not authorized, and the app asks for
permission only when the user toggles the setting (which a default-ON user never does) or
saves a subscription with reminders. So for most users the digest never arrives, and the
rating prompt's "success moment" on tapping a digest never fires.

iOS offers provisional authorization: granted without a prompt, notifications are delivered
quietly to Notification Center with "Keep" / "Turn off" buttons. Both senders already accept
`.provisional`. Requesting it once, after the app has loaded for an onboarded user, turns the
feature on for everyone who has not decided yet, without an intrusive prompt. A later full
request (e.g. subscription reminders) still upgrades it.

## Current state

- `Tenra/Services/Notifications/InsightSignalSettings.swift:66-67` — defaults ON:
  ```swift
  self.isEnabled = (defaults.object(forKey: Self.masterKey) as? Bool) ?? true
  self.weeklyDigestEnabled = (defaults.object(forKey: Self.weeklyDigestKey) as? Bool) ?? true
  ```
- `Tenra/Services/Notifications/WeeklyDigestScheduler.swift:74-75` and
  `Tenra/Services/Notifications/InsightSignalService.swift:260-263`:
  ```swift
  let auth = await center.notificationSettings().authorizationStatus
  guard auth == .authorized || auth == .provisional else { return }
  ```
- `Tenra/Services/Notifications/NotificationPermissionManager.swift` —
  `@MainActor @Observable class NotificationPermissionManager` with `static let shared`,
  `authorizationStatus`, `checkAuthorizationStatus()`, and `requestAuthorization()` which calls
  `center.requestAuthorization(options: [.alert, .sound, .badge])` (full prompt).
- Only callers of `requestAuthorization()`: `InsightSignalSettingsView.swift:60` (toggle),
  `SubscriptionEditView.swift:209` (reminders), and a DEBUG view.
- `Tenra/Views/Home/ContentView.swift:126-132` — the home screen's startup task:
  ```swift
  .task {
      // initializeFastPath() ran in TenraApp ... Only the full initialize() ... still needs to run here.
      await coordinator.initialize()
  }
  ```
  ContentView is shown only after onboarding (TenraApp shows `OnboardingFlowView` while `needsOnboarding`).
- UI tests and the `-ScreenshotDemo` mode must not be disturbed; provisional authorization shows no UI.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/ProvisionalNotificationPolicyTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |

## Scope

**In scope**: `Tenra/Services/Notifications/NotificationPermissionManager.swift`,
`Tenra/Views/Home/ContentView.swift` (one call in the existing `.task`),
`TenraTests/Services/ProvisionalNotificationPolicyTests.swift` (create).

**Out of scope**: a custom pre-prompt screen; changing defaults of `InsightSignalSettings`;
subscription reminder scheduling (separate finding F9).

## Git workflow

Commit directly on `main`; do not push. Message:
`fix(notifications): request provisional permission so the digest and signals are delivered`.

## Steps

### Step 1: Policy + request method

In `NotificationPermissionManager`:
```swift
/// Pure policy, pinned by tests: ask for provisional authorization only when the
/// user has not decided yet AND something that needs notifications is enabled.
nonisolated static func shouldRequestProvisional(
    status: UNAuthorizationStatus,
    signalsEnabled: Bool,
    digestEnabled: Bool
) -> Bool

/// Requests `.provisional` (no system prompt) once, when the policy allows.
func requestProvisionalIfUndetermined() async
```
`requestProvisionalIfUndetermined` refreshes status, reads `InsightSignalSettings.shared.isEnabled`
and `.weeklyDigestEnabled`, and if the policy says yes calls
`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .provisional])`,
then `checkAuthorizationStatus()`. Swallow errors (log nothing sensitive).
Policy: `status == .notDetermined && (signalsEnabled || digestEnabled)`.

**Verify**: Build → SUCCEEDED.

### Step 2: Call it after the full load

In `ContentView`'s startup `.task`, after `await coordinator.initialize()`, add
`await NotificationPermissionManager.shared.requestProvisionalIfUndetermined()`.

**Verify**: Build → SUCCEEDED; `grep -c "requestProvisionalIfUndetermined" Tenra/Views/Home/ContentView.swift` → 1.

### Step 3: Tests

`TenraTests/Services/ProvisionalNotificationPolicyTests.swift` (plain struct):
1. `.notDetermined` + signals on → true.
2. `.notDetermined` + both off → false.
3. `.denied` → false; `.authorized` → false; `.provisional` → false.
4. `.notDetermined` + only digest on → true.

**Verify**: Suite → SUCCEEDED; full TenraTests → 0 failed.

## Done criteria

- [ ] Build SUCCEEDED; policy suite passes; full TenraTests 0 failed
- [ ] `grep -n "provisional" Tenra/Services/Notifications/NotificationPermissionManager.swift` → matches
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 009 updated

## STOP conditions

- ContentView's startup `.task` no longer exists or also runs during onboarding.
- `WeeklyDigestScheduler` / `InsightSignalService` stopped accepting `.provisional`.

## Maintenance notes

- Device check (fresh install, finish onboarding): Settings app → Notifications → Tenra shows
  "Deliver Quietly"; on Monday the digest appears in Notification Center.
- `InsightSignalSettingsView` shows the permission-denied row only for `.denied`; provisional
  users see the toggles, which is correct.
- Next step (not in this plan): a full permission request at a value moment, so digests can
  also appear as banners.
