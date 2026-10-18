# Voice Input Domain

Architecture and gotchas for `VoiceInputView`, `VoiceInputConfirmationView` and
`VoiceInputService`, plus the draft resolution shared with App Intents.

## Self-Contained VoiceInputView

`VoiceInputView` manages its own `.sheet(item:)` for confirmation. **No callback chains to parent** — data flows directly within the view.

## VoiceInputConfirmationView Has Its Own NavigationStack

Present via `.sheet()`, **NEVER via `.navigationDestination()`** (nested `NavigationStack` = empty/broken view).

## Edit-Only Mode (`onUpdate`)

`VoiceInputConfirmationView` `onUpdate` mode:
- Pass `onUpdate: ((ParsedOperation) -> Void)?` for edit-only behavior (returns updated `ParsedOperation` without saving)
- `nil` = save mode
- The returned `subcategoryNames` come from the subcategory picker's ids (the names the screen
  opened with are only its starting point)
- `editsDate: true` adds the add form's date buttons (`dateButtonsSafeArea`); the voice flow
  keeps the date it heard. The assistant's confirm card uses both to edit a draft
  (`AgentDraftEditor`, [plan-ai-assistant.md](../plan-ai-assistant.md) §3.1)

## Live preview cards are not `TransactionCard`

⚠️ `TransactionCard` has built-in tap → edit sheet and swipe actions; inside another gesture
its own gesture intercepts the outer one. `VoiceInputView.previewCard(for:at:)` is a `Button`
around the same layout (`Icon`, `FormattedAmountText`); for other read-only rows use
`TransactionCardView`, which has no gestures or environment dependencies.

## Recognition language

`VoiceInputService` recognizes the language from [`VoiceRecognitionLanguage`](../../Tenra/Services/Voice/VoiceRecognitionLanguage.swift):
the choice in Settings → General → Voice language (`voice.recognitionLanguage` in UserDefaults,
empty = as in the app), else the app's language (`Bundle.main.preferredLocalizations`) with its
own region, the device's region or its usual one, whichever `SFSpeechRecognizer` supports, else
`ru-RU` (what it always used before). The choice is for people who read one language and speak
another. Settings lists the candidates the recognizer supports, Kazakh included. The service
remakes its recognizer at the next recording when the language changed. The rule is a pure
function pinned by `VoiceRecognitionLanguageTests`.

## Audio session must stay off the main actor

`VoiceInputService` is `@MainActor`, but `AVAudioSession.setCategory` / `setActive` are blocking
CoreAudio calls (tens of milliseconds, more on a cold audio stack); on the main actor they
stall running animations, e.g. the voice sheet sliding up while `VoiceInputView.onAppear`
auto-starts recording. iOS 27 logs it:
`AVAudioSession_iOS.mm:978 This method can lead to UI unresponsiveness if called on the main thread`.

All session work therefore goes through [`VoiceAudioSession`](../../Tenra/Services/Voice/VoiceAudioSession.swift),
whose functions are `nonisolated async` (so they run on the cooperative pool, not the caller's
actor) and which uses the asynchronous `activate(options:)` / `deactivate(options:)`
on iOS 27, falling back to the synchronous calls — still off the main thread — on iOS 26.
Never call `AVAudioSession` directly from the service.

The `AVAudioEngine` lifecycle lives off the main actor too, in
[`VoiceRecordingEngine`](../../Tenra/Services/Voice/VoiceRecordingEngine.swift): the first
`inputNode` access, `outputFormat(forBus:)`, `prepare()`, `start()` and `stop()` all block
inside CoreAudio.

⚠️ **Because both helpers suspend, `startRecording` is interruptible.** `VoiceInputService`
guards that with `startToken`: each start claims a token, every `stopRecordingSync` bumps it
(before its own `isRecording` guard, which does not hold yet during startup), and the start
tears the half-built stack down if the token changed. `VoiceInputView.onDisappear` therefore
calls `stopRecording()` unconditionally: `isRecording` is still false while the stack comes up,
and skipping the call then would leave the microphone open behind a dismissed view. Keep both
in place when touching this path.

## Speech Recognition Gotchas

### `cancel()` fires callback with empty/truncated text

⚠️ Guard with:

```swift
guard self.isRecording || self.isStopping else { return }
```

Never overwrite `transcribedText` with empty string.

### Silence detection — text-based

Audio-based VAD is unreliable with background noise, so auto-stop is **text-based**:
`VoiceInputView` restarts a 5-second timer on every `transcribedText` change and stops
recording when it fires. (`VoiceInputService` creates a `SilenceDetector`, the audio-based
detector in `Services/Audio/`, but never feeds it buffers.)

### The voice level

`VoiceRecordingEngine.level(of:)` turns each microphone buffer into its RMS in decibels and maps
−50…−10 dB onto 0…1; the tap reports it through `makeAndStart(…, onLevel:)`, and
`VoiceInputService.audioLevel` takes it on the main actor (back to 0 on stop). Nothing is
recorded or kept. Smoothing is DesignKit's (`EdgeGlow`'s level driver: fast attack, slow
release), so pass the raw level and do not smooth it here.

## The recording screen (DesignKit effects)

`VoiceInputView` while recording (each in its own small view, so the ~47 level updates a second
redraw only it):

- **Edge light:** `VoiceLevelGlow` → DesignKit's `EdgeGlow(level:)`, one Metal colour effect
  along the screen edges.
- **Stop button:** `VoiceStopOrb` → DesignKit's `VoiceOrbButton` (4.14.0: `VoiceWave(level:style: .orb)` with a stop glyph); only the
  orb at rest (80 pt) takes the tap. `handleStopTap` plays `HapticManager.play(.tap)`.
- **Before any text:** `ListeningPrompt` ("Speak...") carries `.thinkingShimmer` in the orb's
  colours (a still gradient under Reduce Motion).
- **First recording ever:** a one-time `.spotlight` round the orb ("Tap the orb when you're
  done…", `voice.tour.orb`), a second after recording starts; lifted by any tap or by stopping.
  Seen-flags live in `FeatureTourState` (UserDefaults), not shown in screenshot mode.
- **The words:** `AnimatedTranscriptionText` → DesignKit's `StreamingText`, recognised
  entities tinted by confidence.
- **Preview cards:** they cascade in 80 ms apart (`.cascadeIn(index:)`); a card deleted from
  its context menu leaves with DesignKit's `DissolveTransition`.

## Speaking to the assistant

The assistant's microphone opens [`AssistantVoiceSheet`](../../Tenra/Views/Assistant/AssistantVoiceSheet.swift):
the same `VoiceLevelGlow`, `ListeningPrompt`, `VoiceStopOrb` and `AnimatedTranscriptionText`,
its own `VoiceInputService`, the 5-second silence stop. Stopped, it shows what it heard; "Ask
Ten" sends it as a message, "Say it again" records anew. There is no local preview: a plain
record ("кофе 1500 и такси 2300") is drafted on the phone by the assistant's FastPath
(`AgentFastPath`, the same `parseMulti`), anything else goes to the model
([plan-ai-assistant.md](../plan-ai-assistant.md) §3.8).

Screenshot mode (`isScreenshotDemo`) passes no level: the glow and the orb breathe on their own.

## Live preview card border

`VoiceInputView.previewCard(for:at:)` applies `.borderGlow` and `.borderBeam` outside
`.cardStyle()`, both with `isActive: beamActive && voiceService.isRecording`, in the category
colour. The effect says the card is updating live from speech; it stops when recording ends
so the post-stop confirmation state stays calm.

- `beamActive` turns on 400 ms after the cards appear (after the entrance spring; running both
  at once hitches) and off in `onDisappear`.
- `isActive == false` removes the overlay entirely (no orphan animation while the
  confirmation sheet is open).
- Match the modifier's `cornerRadius` to the card's — `cardStyle()` defaults to `AppRadius.xl`, which is also `borderBeam`'s default.
- The modifiers are DesignKit's (`docs/motion.md` there); see [gotchas.md](../gotchas.md) for the AngularGradient rotation pitfall.

## Parsing (`VoiceInputParser`)

`parseMulti` (voice, Ten's FastPath, the Log Transaction intent) splits the phrase with
`VoiceInputSegmenter` and parses each clause; `parse` reads one.

- **Amount.** Grouped thousands and decimals in any convention: `decimalAmount` takes a last
  group of one or two digits as decimals ("12,50", "1.234,56"), anything else as thousands
  ("12,000", "1.500", "10 000"). The regexes use digit lookarounds, not `\b`, which finds no
  boundary between a digit and CJK text ("コンビニで500円"). A number next to a currency word
  beats a bare one; a year-shaped bare number (1900-2100) only loses to another amount.
- **CJK units.** `normalizeText` rewrites 億/억, 万/만, 千/천, 百/백 spans as digits
  (`expandCJKNumerals`: "1万2000円", "1만 2천 원" → 12000; "만원", "百円" before 円/원). A unit
  without a digit before it stays text ("千葉"). The segmenter keeps a unit inside the amount
  token, so "1만 2천" stays one clause and FastPath's clause count matches.
- **Currency.** `currencyKeywords`, longest first. A keyword starting with a letter counts only
  at the start of a word ("eur" not in "coiffeur", "원" not in "병원"). "$" and "dollars" read
  in the local currency when it is a dollar (`dollarSignCurrencies` also covers MXN and the
  other peso "$" countries, `dollarNamedCurrencies` only real dollars), else USD; the local
  currency is the named account's, else the default account's. The account is found before
  the currency for that reason. No currency word → the account's currency.
- **Category.** Two maps: `categoryMap` matches anywhere, `wholeWordCategoryMap` (short English
  words: "rent", "bus", "bar", "vet") only as whole words. Keys run longest first with ties
  alphabetical, so the pick never depends on `Dictionary` order. Every target is an onboarding
  preset name in one language (pinned by `VoiceCategoryTargetsTests`); `resolveCategoryName`
  then finds the user's category through `categoryGroups` (each preset under all its names), so
  "groceries" lands in "Продукты" and "lebensmittel" in "Groceries". No keyword → "Other" in any
  language. Adding keywords: a duplicate key across either map traps at runtime; check before
  building.

## Account & category resolution (shared with App Intents)

`TransactionDraftService.makeDraft` (`Services/Intents/`) is the single resolver behind both
`VoiceInputConfirmationView` and every App Intent ([intents.md](intents.md) covers the
intents, blocking issues and commit). It resolves in this order; breaking an invariant is
silent, not loud.

**1. Amount.** Missing or ≤ 0 → `DraftIssue.missingAmount`.

**2. Category, before the account.** Account selection is keyed on the category, and `commit`
records that key using the *resolved* name. Looking the preference up under the parser's raw
guess instead means `VoiceLearningStore` never matches for anyone who renamed a category,
which is most people.

**3. A category miss never blocks the write.** `VoiceInputParser` maps keywords onto preset
names (resolved across languages, see Parsing above) while users rename categories freely. Resolution among
the user's categories of the operation's type widens exact → case-insensitive (both exact) →
substring either way (min 3 chars, first match in user order) → localized `category.other` →
**uncategorized**; anything but an exact match adds `DraftWarning.categorySubstituted`.
`TransactionStore.validate` deliberately accepts an empty category: refusing to record money
the user just spent because a word was unfamiliar is never the right trade.

**4. Account.** Loans and deposits are never eligible (none left → `noEligibleAccount`).
Priority: named in the phrase → confirmed learning (`VoiceLearningStore.preferredAccountID`)
→ `AccountRankingService` history ranking (the `suggestAccount` closure) → first eligible.
Anything but a named account adds `DraftWarning.accountInferred`. The app passes the loaded
store's ranking; intents pass `IntentAccountSuggester`, which fetches one category's history
with a bounded predicate (200 rows) because an intent process has no transactions loaded by
design.

**5. Only record an account the user actually chose.** `commit` skips `recordLearning` when
the draft carries `.accountInferred`. Recording an inferred account creates a
self-reinforcing loop: the guess gets confirmed, two confirmations cross
`VoiceLearningStore`'s confidence threshold, and from then on the learned guess outranks
`AccountRankingService`, so every later transaction lands on whatever account was picked first.

**6. Currency.** Converted only when the operation's currency differs from the account's.
`ConversionPolicy.cachedOnly` reads the FX cache (`CurrencyConverter.convertSync`); a miss is
`needsFXConversion`. Intents treat that as blocking. `VoiceInputConfirmationView` (the user is
present) then runs `await CurrencyConverter.convert(...)` and calls `makeDraft` again with
`.provided(converted)` and the same `suggestAccount`, so the retry picks the account the first pass would; `.provided(nil)` (the network failed too) stays `needsFXConversion`.
