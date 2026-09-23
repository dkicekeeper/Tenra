# Plan 001: Tenra can be locked with Face ID / Touch ID / passcode and hides its screen in the app switcher

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 84fbabdf..HEAD -- Tenra/TenraApp.swift Tenra/Views/Settings/SettingsView.swift Tenra/Services/Settings/RatingPromptService.swift Tenra/Info.plist Tenra/*.lproj/Localizable.strings`
> If any of these changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S (about one day including 11 locales)
- **Risk**: MED (a new window above the app; a bug here can block the user out of their own data)
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `84fbabdf`, 2026-09-24

## Why this matters

Tenra's core positioning is "100% private finance tracker, no bank login"
(`app-marketing-context.md`, "Unique Differentiator"). Yet the app has no lock
at all: `grep -rn "LocalAuthentication\|LAContext" Tenra` returns nothing, and
nothing hides balances in the iOS app switcher. Competing CIS finance apps
(CoinKeeper, Zenmoney) offer an in-app PIN / Face ID lock, and users look for
it in Settings. This plan adds an opt-in lock (default OFF) that asks for
Face ID / Touch ID / device passcode on launch and after the app was in the
background for 60 seconds or more, and covers the screen while the app is not
active so the app-switcher snapshot shows no amounts.

Context the executor should know: since iOS 18 users can also lock any app
from the Home Screen ("Require Face ID"). This in-app lock is complementary
(discoverable in Settings, visible state, marketing claim). If a user enables
both, they get two prompts; that is acceptable and not something to solve here.

## Current state

- `Tenra/TenraApp.swift` — `@main` App. Holds `@Environment(\.scenePhase)` and
  reacts to phase changes at lines 76-115:
  ```swift
  // Tenra/TenraApp.swift:76
  .onChange(of: scenePhase) { _, phase in
      ...
      if phase == .active {
          let center = UNUserNotificationCenter.current()
          center.setBadgeCount(0)
          ...
          RatingPromptService.shared.recordSession()
          ...
      }
      if phase == .background {
          // Ask iOS for a background insights recompute while we're away.
          BackgroundInsightsRefresher.shared.scheduleNextRefresh()
      }
  }
  ```
  The App struct currently has no `init()`. Its content is a `ZStack` with
  `MainTabView` / `OnboardingFlowView`. **Important:** sheets and full-screen
  covers presented by `MainTabView` and its children are UIKit presentations
  that sit ABOVE any SwiftUI view in this ZStack. A lock view placed in the
  ZStack would NOT cover an open sheet (e.g. the add-transaction modal). That is
  why this plan uses a separate `UIWindow` with a high `windowLevel`.

- `Tenra/Views/Settings/SettingsView.swift` — Settings list, lines 64-78:
  ```swift
  List {
      SettingsProSection()
      generalSection
      notificationsSection
      SettingsSiriSection()
      cloudSection
      exportImportSection
      dangerZoneSection
      #if DEBUG
      experimentsSection
      #endif
      aboutSection
  }
  ```

- `Tenra/Views/Settings/SettingsSiriSection.swift` — exemplar of a
  self-contained Settings section with no props (header + footer via
  `Section { } header: { } footer: { }`). Match this shape.

- `Tenra/Services/Notifications/InsightSignalSettings.swift` — exemplar of a
  `@MainActor @Observable final class` singleton backed by `UserDefaults`,
  with an injectable `defaults` and `didSet` persistence:
  ```swift
  @MainActor
  @Observable
  final class InsightSignalSettings {
      static let shared = InsightSignalSettings()
      private static let masterKey = "insightSignals.enabled"
      @ObservationIgnored private let defaults: UserDefaults
      var isEnabled: Bool {
          didSet { defaults.set(isEnabled, forKey: Self.masterKey) ... }
      }
      init(defaults: UserDefaults = .standard) { ... }
  ```

- `Tenra/Views/Settings/InsightSignalSettingsView.swift` — exemplar of a
  `Toggle` driven through a custom `Binding` (`masterBinding`).

- `Tenra/Services/Settings/RatingPromptService.swift:151-156` — decides whether
  the rating survey may be presented:
  ```swift
  private static var isScreenClear: Bool {
      guard let scene = UIApplication.shared.connectedScenes
          .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.keyWindow?.rootViewController else { return false }
      return root.presentedViewController == nil
  }
  ```
  Without a change it would present the survey underneath the lock window.

- `Tenra/Info.plist` — privacy usage strings are plain English/Russian values
  directly in the plist (e.g. `NSCameraUsageDescription`); there is no
  `InfoPlist.strings` in any `.lproj`. `NSFaceIDUsageDescription` is absent.
  Without it, Face ID evaluation crashes / is denied at runtime.

- Localization: 11 locales in `Tenra/{en,ru,de,es,fr,tr,pt-BR,it,uk,ja,ko}.lproj/Localizable.strings`,
  all currently 1677 lines with identical key sets. Every new key must be added
  to ALL 11 files. None of the keys introduced below exist yet (verified:
  `grep -nE '^"(settings\.privacy\.|settings\.appLock|appLock\.)' Tenra/en.lproj/Localizable.strings`
  returns nothing; note that `"settings.privacyPolicy"` exists and is unrelated).

- Project conventions:
  - Xcode uses file-system-synchronized groups: creating a `.swift` file on
    disk adds it to the target. Never edit `project.pbxproj`.
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: types are MainActor unless
    marked `nonisolated`. Test suites that construct MainActor types must be
    annotated `@MainActor`.
  - Design tokens: `AppColors`, `AppSpacing`, `AppTypography`, `AppRadius`,
    `BounceButtonStyle` (see the accent button in
    `Tenra/Views/Import/ReceiptConfirmationView.swift`, `addButton`).
  - No em dashes (—) in any user-facing string, in any locale.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **`, no `error:` lines |
| Unit tests (one suite) | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/AppLockServiceTests 2>&1 \| grep -aE "Test run with .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | `Test run with N tests ... passed`, `** TEST SUCCEEDED **` |
| Locale parity | `for L in ru de es fr tr pt-BR it uk ja ko; do diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings) <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings) > /dev/null && echo "$L ok" \|\| echo "$L MISMATCH"; done` | 10 lines, all `ok` |

Notes: `-only-testing` must name the suite TYPE (`AppLockServiceTests`), never a
method (method-level filtering silently runs 0 tests). If xcodebuild says
"database is locked", wait 5 s and retry. A bare `name=iPhone 17 Pro` without
`OS=` fails on this machine; use the destination above.

## Suggested executor toolkit

- `swiftui-expert:swiftui-expert-skill` for the overlay view and Settings section.
- `swift-testing-expert:swift-testing-expert` for the test suite.
- Read `docs/design-system.md` (tokens) before writing views.

## Scope

**In scope** (the only files you should modify or create):
- `Tenra/Services/Settings/AppLockService.swift` (create)
- `Tenra/Views/Home/AppLockOverlayView.swift` (create)
- `Tenra/Views/Settings/SettingsPrivacySection.swift` (create)
- `Tenra/Views/Settings/SettingsView.swift` (insert one line)
- `Tenra/TenraApp.swift` (add `init()` and one call in the scenePhase handler)
- `Tenra/Services/Settings/RatingPromptService.swift` (one condition in `isScreenClear`)
- `Tenra/Info.plist` (add `NSFaceIDUsageDescription`)
- `Tenra/*.lproj/Localizable.strings` (all 11, append keys)
- `TenraTests/Services/AppLockServiceTests.swift` (create)

**Out of scope** (do NOT touch):
- A "hide amounts" / privacy mode for balances. Amounts render through several
  components (`FormattedAmountText`, `InfoRow`, `Formatting.formatCurrencySmart`
  strings); masking them is a separate design.
- A grace-period picker. The grace period is a fixed 60 seconds.
- Localizing `Info.plist` usage strings via `InfoPlist.strings`. The existing
  strings are not localized either; that is a separate cleanup.
- `AppDelegate.swift`, App Intents files, `BackgroundInsightsRefresher` — the
  lock must not change their behavior (they run without UI).
- `project.pbxproj`.

## Git workflow

- The maintainer commits directly to `main` (no feature branches, no worktrees).
  Commit on the current branch; do NOT push.
- Conventional commits, matching `git log`, e.g.
  `feat(privacy): optional Face ID lock with app-switcher cover`.
- End the commit message with the co-author line the operator gives you, if any.

## Steps

### Step 1: Add the lock service

Create `Tenra/Services/Settings/AppLockService.swift` containing three things.

1. An authenticator seam:
   ```swift
   import Foundation
   import LocalAuthentication
   import Observation
   import SwiftUI

   enum AppLockBiometry: Equatable { case faceID, touchID, passcodeOnly, unavailable }

   protocol AppLockAuthenticating {
       /// What the device can do right now. `.unavailable` = no passcode set.
       func biometry() -> AppLockBiometry
       /// Face ID / Touch ID with automatic passcode fallback. Never throws; false on cancel/failure.
       func authenticate(reason: String) async -> Bool
   }

   struct LocalAppLockAuthenticator: AppLockAuthenticating {
       func biometry() -> AppLockBiometry {
           let context = LAContext()
           var error: NSError?
           guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
           switch context.biometryType {
           case .faceID: return .faceID
           case .touchID: return .touchID
           default: return .passcodeOnly
           }
       }
       func authenticate(reason: String) async -> Bool {
           let context = LAContext()
           var error: NSError?
           guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
           do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
           catch { return false }
       }
   }
   ```
   Use `.deviceOwnerAuthentication` (biometrics with passcode fallback), NOT
   `.deviceOwnerAuthenticationWithBiometrics`: a user whose Face ID fails must
   still be able to get in with the passcode.

2. The service, modeled on `InsightSignalSettings`:
   ```swift
   @MainActor
   @Observable
   final class AppLockService {
       static let shared = AppLockService()

       nonisolated static let gracePeriod: TimeInterval = 60
       private static let enabledKey = "appLock.enabled"

       /// Pure relock rule, pinned by AppLockServiceTests.
       nonisolated static func shouldLock(isEnabled: Bool, backgroundedAt: Date?, now: Date) -> Bool {
           guard isEnabled, let backgroundedAt else { return false }
           return now.timeIntervalSince(backgroundedAt) >= gracePeriod
       }

       @ObservationIgnored private let defaults: UserDefaults
       @ObservationIgnored private let now: () -> Date
       @ObservationIgnored let authenticator: AppLockAuthenticating
       /// Wired once in TenraApp.init to AppLockWindowPresenter. Tests leave it nil.
       @ObservationIgnored var onOverlayVisibilityChange: ((Bool) -> Void)?
       @ObservationIgnored private var backgroundedAt: Date?
       @ObservationIgnored private var isAuthenticating = false

       var isEnabled: Bool {
           didSet {
               defaults.set(isEnabled, forKey: Self.enabledKey)
               if !isEnabled { isLocked = false; isSceneObscured = false }
           }
       }
       private(set) var isLocked: Bool { didSet { notifyOverlay() } }
       private(set) var isSceneObscured = false { didSet { notifyOverlay() } }

       var shouldShowOverlay: Bool { isLocked || isSceneObscured }

       init(defaults: UserDefaults = .standard,
            now: @escaping () -> Date = { Date() },
            authenticator: AppLockAuthenticating = LocalAppLockAuthenticator()) {
           self.defaults = defaults
           self.now = now
           self.authenticator = authenticator
           let enabled = defaults.bool(forKey: Self.enabledKey)
           self.isEnabled = enabled
           self.isLocked = enabled   // cold launch starts locked when enabled
       }
       ...
   }
   ```
   Then implement:
   - `func handleScenePhase(_ phase: ScenePhase)`:
     - `.background`: `backgroundedAt = now()`; `isSceneObscured = isEnabled`.
     - `.inactive`: `isSceneObscured = isEnabled` (covers the app switcher; also
       fires under the Face ID sheet, which is fine because the lock is shown then).
     - `.active`: `isSceneObscured = false`; if
       `Self.shouldLock(isEnabled:backgroundedAt:now:)` then `isLocked = true`;
       then set `backgroundedAt = nil` (this is what prevents a relock loop after
       the Face ID sheet returns the app to `.active`); if `isLocked`, start
       `Task { await unlock() }`.
     - `@unknown default`: do nothing.
   - `func unlock() async`: `guard isLocked, !isAuthenticating else { return }`;
     set `isAuthenticating = true`, `defer { isAuthenticating = false }`;
     `if await authenticator.authenticate(reason: String(localized: "appLock.reason")) { isLocked = false }`.
   - `func setEnabled(_ enabled: Bool) async -> Bool` for the Settings toggle:
     turning ON requires a successful `authenticator.authenticate(...)` first
     (so a user can never enable a lock they cannot open); on success set
     `isEnabled = true` and return true; on failure leave it off and return
     false. Turning OFF sets `isEnabled = false` immediately and returns true.
   - `private func notifyOverlay() { onOverlayVisibilityChange?(shouldShowOverlay) }`.

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 2: Write the tests (before wiring UI)

Create `TenraTests/Services/AppLockServiceTests.swift`, modeled on
`TenraTests/Services/RatingPromptServiceTests.swift` (swift-testing,
`import Testing`, `@testable import Tenra`). Annotate the suite `@MainActor`.
Use a fresh `UserDefaults(suiteName: "AppLockServiceTests.\(UUID().uuidString)")!`
per test, a mutable clock (`var current = Date(timeIntervalSince1970: 1_000_000)`
captured by the `now` closure through a small reference box class), and a
`FakeAuthenticator: AppLockAuthenticating` with a settable `result: Bool` and a
`callCount`.

Cases (see Test plan for the full list). All state assertions right after
`handleScenePhase` are synchronous; call `await service.unlock()` explicitly
when a test needs the authentication outcome.

**Verify**: Unit test command → `** TEST SUCCEEDED **`, suite reports at least 9 tests passed.

### Step 3: Add the overlay window and view

Create `Tenra/Views/Home/AppLockOverlayView.swift` with:

1. `struct AppLockOverlayView: View` reading `AppLockService.shared` (hold it as
   `@State private var lock = AppLockService.shared`, same as
   `InsightSignalSettingsView` holds its singleton). Layout: full-screen
   `AppColors.bgBase.ignoresSafeArea()`, centered `VStack(spacing: AppSpacing.lg)`
   with `Image(systemName: "lock.fill")` in `AppColors.accent`, the text
   `"Tenra"` in `AppTypography.h4`, and ONLY when `lock.isLocked` a subtitle
   `String(localized: "appLock.title")` and an accent button
   `String(localized: "appLock.unlock")` styled like `ReceiptConfirmationView`'s
   `addButton` (accent background, white text, `AppRadius.button`,
   `BounceButtonStyle()`), whose action is `Task { await lock.unlock() }`.

2. `@MainActor final class AppLockWindowPresenter` with `static let shared` and
   `func setVisible(_ visible: Bool)`:
   - When visible: if `window == nil`, find
     `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first`
     (return if nil), create `UIWindow(windowScene:)`, set
     `windowLevel = .alert + 1`, `rootViewController = UIHostingController(rootView: AppLockOverlayView())`;
     then `window?.isHidden = false`. Do NOT call `makeKeyAndVisible()`
     (it would steal key status and keyboard focus from the main window;
     touches reach the topmost visible window regardless of key status).
   - When not visible: `window?.isHidden = true`.

**Verify**: Build command → `** BUILD SUCCEEDED **`.

### Step 4: Wire into the app lifecycle

In `Tenra/TenraApp.swift`:
- Add `import` nothing new. Add an initializer:
  ```swift
  init() {
      AppLockService.shared.onOverlayVisibilityChange = { visible in
          AppLockWindowPresenter.shared.setVisible(visible)
      }
  }
  ```
- In the existing `.onChange(of: scenePhase) { _, phase in ... }` closure, add
  as the FIRST statement: `AppLockService.shared.handleScenePhase(phase)`.
  Leave every existing line untouched.

In `Tenra/Services/Settings/RatingPromptService.swift`, change `isScreenClear`'s
last line to `return root.presentedViewController == nil && !AppLockService.shared.shouldShowOverlay`.

In `Tenra/Info.plist`, add (next to the other `NS...UsageDescription` keys):
```xml
<key>NSFaceIDUsageDescription</key>
<string>Tenra uses Face ID to keep your finances locked when you turn on the app lock.</string>
```

**Verify**:
- Build command → `** BUILD SUCCEEDED **`.
- `grep -c "AppLockService.shared.handleScenePhase(phase)" Tenra/TenraApp.swift` → `1`
- `plutil -lint Tenra/Info.plist` → `Tenra/Info.plist: OK`

### Step 5: Settings section

Create `Tenra/Views/Settings/SettingsPrivacySection.swift`, shaped like
`SettingsSiriSection` (self-contained, no props):
- `@State private var lock = AppLockService.shared`
- `@State private var biometry: AppLockBiometry = .unavailable`, refreshed in
  `.task { biometry = lock.authenticator.biometry() }`.
- `Section { Toggle(title, isOn: binding) .disabled(biometry == .unavailable) } header: { Text("settings.privacy.header") } footer: { Text(biometry == .unavailable ? "settings.appLock.unavailable" : "settings.appLock.footer") }`
- Title by biometry: `.faceID` → `"settings.appLock.faceID"`, `.touchID` →
  `"settings.appLock.touchID"`, otherwise `"settings.appLock.passcode"`
  (use `String(localized:)`).
- Binding: `get: { lock.isEnabled }`, `set: { newValue in Task { _ = await lock.setEnabled(newValue) } }`.
  If authentication fails when enabling, the toggle simply stays off.

In `SettingsView.swift`, insert `SettingsPrivacySection()` on its own line
directly after `generalSection` in the `List`.

**Verify**: Build command → `** BUILD SUCCEEDED **`;
`grep -c "SettingsPrivacySection()" Tenra/Views/Settings/SettingsView.swift` → `1`.

### Step 6: Localize (all 11 locales)

Append these 9 keys to the END of every `Tenra/<L>.lproj/Localizable.strings`.
English and Russian values are given; translate the other 9 locales
(de, es, fr, tr, pt-BR, it, uk, ja, ko) naturally. Rules: no em dashes (—)
anywhere; keep "Face ID", "Touch ID", "Tenra" untranslated; these strings have
no format specifiers, so do not add any.

| Key | en | ru |
|---|---|---|
| `settings.privacy.header` | Privacy | Конфиденциальность |
| `settings.appLock.faceID` | Lock with Face ID | Блокировка Face ID |
| `settings.appLock.touchID` | Lock with Touch ID | Блокировка Touch ID |
| `settings.appLock.passcode` | Lock with passcode | Блокировка код-паролем |
| `settings.appLock.footer` | Tenra asks for Face ID, Touch ID or your passcode after you have been away for more than a minute, and hides its screen in the app switcher. | Tenra запросит Face ID, Touch ID или код-пароль, если вас не было дольше минуты, и скроет экран в переключателе приложений. |
| `settings.appLock.unavailable` | Set up a passcode in iOS Settings to lock Tenra. | Чтобы включить блокировку, задайте код-пароль в настройках iOS. |
| `appLock.title` | Tenra is locked | Tenra заблокирована |
| `appLock.unlock` | Unlock | Разблокировать |
| `appLock.reason` | Unlock to see your finances | Разблокируйте, чтобы увидеть свои финансы |

Write the files with `python3` using `io.open(path, encoding="utf-8")` in
append mode. Do NOT use `perl -CSD` or `sed -i` for non-ASCII text (it has
produced mojibake in this repo before).

**Verify**:
- Locale parity command → all 10 locales `ok`.
- `grep -c '^"appLock.unlock"' Tenra/*.lproj/Localizable.strings` → every file `:1`.
- `grep -n "appLock.title" Tenra/ru.lproj/Localizable.strings Tenra/ja.lproj/Localizable.strings` shows readable Cyrillic / Japanese (no `Ã`, `Ð` sequences).
- `grep -n '—' Tenra/*.lproj/Localizable.strings | grep -E 'appLock|settings\.privacy\.'` → no output.
- Build command → `** BUILD SUCCEEDED **`.

### Step 7: Full test run

**Verify**: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests 2>&1 | grep -aE "Test run with .* (passed|failed)|Executed [0-9]+ tests|\*\* TEST (SUCCEEDED|FAILED)"`
→ `** TEST SUCCEEDED **`. (If it prints `** TEST FAILED **` with zero failing
test names, it is a known harness flake: re-run once.)

## Test plan

File: `TenraTests/Services/AppLockServiceTests.swift`, `@MainActor struct AppLockServiceTests`.

1. `shouldLock` pure rule: disabled → false; enabled + nil backgroundedAt → false;
   59 s → false; exactly 60 s → true.
2. Cold launch: defaults with `appLock.enabled = true` → `isLocked == true`;
   with the key absent → `isLocked == false`, `isEnabled == false`.
3. Short absence: enabled, unlocked (set up by `setEnabled(true)` with a
   succeeding fake, which leaves `isLocked == false`) → `.background` at t0 →
   `.active` at t0+30 s → `isLocked == false`.
4. Long absence: same but t0+61 s → `isLocked == true`.
5. `unlock()` success → `isLocked == false`; failure → stays `true`.
6. No relock loop: long absence → locked → `.inactive` → `.active` →
   `await unlock()` with success → `isLocked == false`, and a further
   `.active` without a new `.background` keeps it `false`.
7. `setEnabled(true)` with a failing fake → returns false, `isEnabled == false`.
8. `setEnabled(false)` while locked → `isLocked == false`, `isEnabled == false`.
9. Obscuring: enabled → `.inactive` → `isSceneObscured == true`; `.active` →
   `false`. Disabled → `.inactive` → stays `false`.
10. Persistence: `setEnabled(true)` succeeds → a new `AppLockService` built on
    the same `UserDefaults` suite starts with `isEnabled == true` and `isLocked == true`.

## Done criteria

- [ ] Build command prints `** BUILD SUCCEEDED **`
- [ ] `AppLockServiceTests` passes with at least 10 tests
- [ ] Full `TenraTests` run prints `** TEST SUCCEEDED **`
- [ ] Locale parity: all 10 non-English locales `ok`; each file has exactly 9 new keys
- [ ] `grep -rn "NSFaceIDUsageDescription" Tenra/Info.plist` → 1 match
- [ ] `git status --short` lists only the in-scope files (plus `UserInterfaceState.xcuserstate`, which Xcode touches on its own)
- [ ] `plans/README.md` status row for 001 updated

## STOP conditions

- The `.onChange(of: scenePhase)` block in `TenraApp.swift` or the `isScreenClear`
  property no longer matches the excerpts above.
- The build fails because `UIWindow(windowScene:)` / `UIHostingController`
  cannot be used from `AppLockOverlayView.swift` (e.g. isolation errors you
  cannot fix inside the in-scope files).
- You find yourself needing to change `AppDelegate.swift`, any file under
  `Tenra/Intents/`, or `MainTabView.swift` to make the lock work.
- The full test run fails in a suite you did not touch, twice in a row.

## Maintenance notes

- Human device check (the executor cannot do this; list it in your report):
  on the physical iPhone enable the lock, then (a) open the add-transaction
  sheet, go Home, wait 60 s, return: the lock must cover the open sheet;
  (b) swipe to the app switcher: the card must show the cover, no amounts;
  (c) cancel Face ID, then tap Unlock: the passcode fallback must work;
  (d) run a Siri "Log a transaction in Tenra" phrase while locked: the
  background intent must still save; (e) disable the device passcode:
  the toggle must be disabled with the "unavailable" footer.
- Anything that presents its own window above the app (a future toast window,
  a debug overlay) must use a `windowLevel` below `.alert + 1`, or it will
  cover the lock.
- The StoreKit purchase sheet makes the app `.inactive`, so the privacy cover
  shows behind it while the lock is enabled. This is expected.
- Deferred: a "hide amounts" privacy mode; localizing Info.plist usage strings
  through `InfoPlist.strings` (all of them, not just Face ID).
