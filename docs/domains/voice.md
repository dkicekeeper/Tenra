# Voice Input Domain

Architecture and gotchas for `VoiceInputView` and `VoiceInputConfirmationView`.

## Self-Contained VoiceInputView

`VoiceInputView` manages its own `.sheet(item:)` for confirmation. **No callback chains to parent** — data flows directly within the view.

## VoiceInputConfirmationView Has Its Own NavigationStack

Present via `.sheet()`, **NEVER via `.navigationDestination()`** (nested `NavigationStack` = empty/broken view).

## Edit-Only Mode (`onUpdate`)

`VoiceInputConfirmationView` `onUpdate` mode:
- Pass `onUpdate: ((ParsedOperation) -> Void)?` for edit-only behavior (returns updated `ParsedOperation` without saving)
- `nil` = save mode (legacy)

## TransactionCard Cannot Be Used as Read-Only Preview

⚠️ `TransactionCard` has built-in `.onTapGesture` + `.sheet` — inner gesture intercepts outer.

Build a custom preview card with `Button` + same subcomponents (`Icon`, `FormattedAmountView`).

## Audio session must stay off the main actor

`VoiceInputService` is `@MainActor`, but `AVAudioSession.setCategory` / `setActive` are blocking
CoreAudio calls (tens of milliseconds, more on a cold audio stack). Calling them inline stalled
whatever animation was running — the visible symptom was a hitch when the "+" tab expands and
`VoiceInputView.onAppear` auto-starts recording. iOS 27 also logs it outright:
`AVAudioSession_iOS.mm:978 This method can lead to UI unresponsiveness if called on the main thread`.

All session work therefore goes through [`VoiceAudioSession`](../../Tenra/Services/Voice/VoiceAudioSession.swift),
whose functions are `nonisolated async` (so they run on the cooperative pool, not the caller's
actor) and which uses the genuinely asynchronous `activate(options:)` / `deactivate(options:)`
on iOS 27, falling back to the synchronous calls — still off the main thread — on iOS 26.
Never call `AVAudioSession` directly from the service again.

The `AVAudioEngine` lifecycle moved off the main actor too, into
[`VoiceRecordingEngine`](../../Tenra/Services/Voice/VoiceRecordingEngine.swift): the first
`inputNode` access, `outputFormat(forBus:)`, `prepare()`, `start()` and `stop()` all block
inside CoreAudio.

⚠️ **Because both helpers suspend, `startRecording` is now interruptible.** `VoiceInputService`
guards that with `startToken`: each start claims a token, every `stopRecordingSync` bumps it
(before its own `isRecording` guard, which does not hold yet during startup), and the start
tears the half-built stack down if the token changed. `VoiceInputView.onDisappear` therefore
calls `stopRecording()` unconditionally — the old `if voiceService.isRecording` check skipped
the call during startup and left the microphone open behind a dismissed view. Keep both
properties in place when touching this path.

## Speech Recognition Gotchas

### `cancel()` fires callback with empty/truncated text

⚠️ Guard with:

```swift
guard self.isRecording || self.isStopping else { return }
```

Never overwrite `transcribedText` with empty string.

### Silence detection — text-based VAD

Audio-based VAD is unreliable with background noise. Use **text-based timeout**:
- Reset timer on every `transcribedText` change
- Auto-stop after N seconds of no new text

### The voice level (DesignKit 2.4.0+)

`VoiceRecordingEngine.level(of:)` turns each microphone buffer into its RMS in decibels and maps
−50…−10 dB onto 0…1; the tap reports it through `makeAndStart(onLevel:)`, and
`VoiceInputService.audioLevel` takes it on the main actor (back to 0 on stop). Nothing is
recorded or kept. Smoothing is DesignKit's (`VoiceLevelDriver`: fast attack, slow release), so
pass the raw level and do not smooth it here.

## The recording screen (DesignKit effects)

`VoiceInputView` while recording (each in its own small view, so the ~47 level updates a second
redraw only it):

- **Edge light:** `VoiceLevelGlow` → DesignKit's `EdgeGlow(level:)`, one Metal colour effect
  along the screen edges (the old `SiriGlow` `MeshGradient` is gone; `SiriGlow` / `SiriWave` are
  deprecated typealiases until DesignKit 3.0).
- **Stop button:** `VoiceStopOrb` → `VoiceWave(level:style: .orb)` with a stop glyph; only the
  orb at rest (80 pt) takes the tap. `handleStopTap` plays `HapticManager.play(.tap)`.
- **Before any text:** `ListeningPrompt` ("Speak...") carries `.thinkingShimmer` in the orb's
  colours (a still gradient under Reduce Motion).
- **First recording ever:** a one-time `.spotlight` round the orb ("Tap the orb when you're
  done…", `voice.tour.orb`), a second after recording starts; lifted by any tap or by stopping.
  Seen-flags live in `FeatureTourState` (UserDefaults), not shown in screenshot mode.
- **The words:** `AnimatedTranscriptionText` → DesignKit's `StreamingText` (2.9.0), recognised
  entities tinted by confidence.
- **Preview cards:** they cascade in 80 ms apart (`.cascadeIn(index:)`, 2.9.0); a card deleted
  from its context menu dissolves (`.dissolve`, 2.7.0).

Screenshot mode (`isScreenshotDemo`) passes no level: the glow and the orb breathe on their own.

## Live Preview Card Border Beam

`VoiceInputView.previewCard(for:)` applies `.borderBeam(isActive: voiceService.isRecording)` outside `.cardStyle()`. The beam is a visual cue that the card is updating live from speech; it stops when recording ends so the post-stop confirmation state stays calm.

- The modifier is `TimelineView`-driven, so `isActive == false` removes the overlay entirely (no orphan animation while the confirmation sheet is open).
- Match the modifier's `cornerRadius` to the card's — `cardStyle()` defaults to `AppRadius.xl`, which is also `borderBeam`'s default.
- See [design-system.md](../design-system.md) for the modifier reference and [gotchas.md](../gotchas.md) for the AngularGradient rotation pitfall.

## Account & category resolution (shared with App Intents)

`TransactionDraftService` (`Services/Intents/`) is the single resolver behind both
`VoiceInputConfirmationView` and every App Intent. Three invariants there were each
established by a real bug; breaking one is silent, not loud.

**1. Resolve the category before the account.** Account selection is keyed on the category,
and `commit` records that key using the *resolved* name. Looking the preference up under the
parser's raw guess instead means `VoiceLearningStore` never matches for anyone who renamed a
category, which is most people.

**2. Never let a category miss block the write.** `VoiceInputParser` maps keywords onto
hardcoded names (`"кофе"` → `"Еда"`) while users rename categories freely. Resolution widens
exact → case-insensitive → substring either way (min 3 chars, first match in user order) →
localized `category.other` → **uncategorized**. `TransactionStore.validate` deliberately
accepts an empty category, so refusing to record money the user just spent because a word was
unfamiliar is never the right trade.

**3. Only record an account the user actually chose.** `commit` skips `recordLearning` when
the draft carries `.accountInferred`. Recording an inferred account creates a
self-reinforcing loop: the guess gets confirmed, two confirmations cross
`VoiceLearningStore`'s confidence threshold, and from then on the learned guess outranks
`AccountRankingService`. Every later transaction lands on whatever account was picked first.
This shipped once and looked like "it always picks the same old account".

Account priority: named in the phrase → confirmed learning → `AccountRankingService` history
ranking → first eligible. Intents get the ranking through `IntentAccountSuggester`, which
fetches one category's history with a bounded predicate (200 rows) because an intent process
has no transactions loaded by design.
