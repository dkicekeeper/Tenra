# The AI assistant (Ten)

Domain reference for Ten, Tenra's AI finance assistant: the app side (`Tenra/Services/Agent/`,
`Tenra/ViewModels/AssistantViewModel.swift`, `Tenra/Views/Assistant/`), the server
(`server/assistant/`, a Cloudflare Worker) and the protocol between them. Ten shipped in 1.6
(2026-10-19). Open work (the Apple models and Siri on iOS 27) is
[plan-assistant-ios27.md](../plan-assistant-ios27.md); smaller open items are in
[backlog.md](../backlog.md). The original design with its reasoning is archived in
[archive/plans/plan-ai-assistant.md](../archive/plans/plan-ai-assistant.md).

---

## 1. What Ten does

One chat for what a person tells the app and asks it:

| Mode | Example | What comes back |
|---|---|---|
| **Ask** | "How much did I spend on food in October?" | Cards: a metric, a chart, transactions, budgets, an "Open category" button |
| **Do** | "Coffee 1500 and a taxi 2300 from Kaspi", typed or spoken | Draft cards to save or edit; "Undo" after saving |
| **Attach** | A receipt photo, a PDF or CSV statement | A summary card; the app's own review screen saves it |
| **Writes first** | (by itself) "The café budget is almost gone" | A "Ten writes" card on Home; "Go through it" opens a chat |
| **Plan** | "How much can I spend a day until payday?" | A daily amount and the balance forecast with what-ifs |

**Where it runs.** Only where the app has a server address (`TenraAssistantURL` in Info.plist) and
the device has App Attest. There the action tab ("+") is Ten (`CreatureTabLabel`) and the
assistant is that tab's page (`AssistantTab`); elsewhere (Simulator, Mac, no App Attest) "+" stays
"Voice | Import". iOS 26+.

**Entry points** (`AssistantEntryPoints`): the tab; "Ask Ten" in the "…" menu of an account,
category, goal and debt, and as a button with Ten's glyph in an insight and History (the
assistant opens with questions about that object, nothing is sent until one is chosen); "Go through
it" on a Home notice; a PDF or CSV opened in Tenra from another app.

## 2. Architecture

```
 Ten's tab / entry points / "Open in Tenra" / "Ten writes" on Home
                    │
          AssistantViewModel  ── the thread, streaming, Ten's mood, the allowance
           ├─ AgentFastPath: VoiceInputParser.parseMulti → a draft without a model ("coffee 1500")
           └─ AgentConversation: one turn until render_reply
                ├─ AgentServerClient → server (Cloudflare Worker) → Claude
                └─ FinanceToolkit (on the phone): read, draft and plan tools
                    │
          AssistantReplyView: AgentReply's blocks → the app's own cards
                    │
          TransactionStore, InsightsService, CategoryBudgetService, BalanceCoordinator,
          TransactionDraftService, RecurringStore, GoalStore, DebtStore … (rules unchanged)
```

There is one model, Claude through the server. A router between `AgentConversation` and the server
(`AgentBrain`: Apple on device, Apple Private Cloud Compute) is the open work of
[plan-assistant-ios27.md](../plan-assistant-ios27.md).

**App side, `Tenra/Services/Agent/`:**

| File | What it does |
|---|---|
| `JSONValue`, `AgentWire` | content blocks kept losslessly, the SSE parser (an event also ends at the next `event:` line: `URLSession.lines` drops empty lines) |
| `AgentServerClient` | `POST /v1/turn` to `TenraAssistantURL`; no address, no assistant and no tab |
| `AgentAttestation` | the App Attest key (§8) |
| `AgentConversation` | the loop: stream, tools on the phone, `tool_result`, until `render_reply`; a failed turn is rolled back; `reset()` starts a new thread |
| `FinanceToolkit` (+ `Compute`, `+ Plans`) | the tools (§3); totals through `SummaryCalculator`, sweeps off the main actor |
| `AgentContextBuilder`, `AgentContextSnapshot+Store` | the `<app_context>` block; its language is the app's |
| `AgentReply`, `AgentReplyData`, `AgentPartialReply`, `AgentReplyMarkdown` | the reply's blocks and their data by reference (§4) |
| `AgentDrafts` (`AgentDraftBook`), `AgentDraftEditor`, `AgentFastPath` | drafts, editing one before saving, the parser path |
| `AgentThreadStore`, `AgentMemory` (`AgentFactStore`) | threads and facts (§5) |
| `AssistantInbox` | "Ten writes" (§6) |
| `AgentAttachment` | an attached receipt or statement (§7) |

The screen: `ViewModels/AssistantViewModel` (the thread, the step named after the running tool, a
failed question with "Retry", `<app_context>` only when it changed) and `Views/Assistant/`.

## 3. Tools (`FinanceToolkit`)

The schemas live on the server (`server/assistant/src/tools.ts`); the phone runs a tool by its
name (`FinanceToolkit.execute`). **Tools always run on the phone**: the model never sees the
database, only the results of the tools it asked for.

| Group | Tools | Built on |
|---|---|---|
| Read | `get_spending_summary`, `compare_periods`, `search_transactions`, `get_accounts`, `get_budgets`, `list_recurring`, `get_insights` (+ health score), `get_goals`, `get_debts`, `convert_currency` | `SummaryCalculator` / `TransactionType.summaryContribution`, `TransactionQueryService`, `BalanceCoordinator`, `CategoryBudgetService.budgetProgress`, `InsightsService`, `SpendingQueryService` |
| Draft | `draft_transactions`, `draft_budget`, `draft_recurring`, `draft_goal`, `draft_goal_contribution`, `draft_debt`, `draft_debt_repayment`, `draft_fact` | `TransactionDraftService.makeDraft` → `commit`, `CategoriesViewModel.setBudget`, `SubscriptionCreationService` + `linkSubcategoriesToTransaction` (red flag 5), `GoalStore`, `DebtStore`, `AgentMemory` |
| Plan | `forecast_balance` (a daily limit until a date, what-ifs), `simulate_loan` (refinancing, early repayment, an extra payment each month), `project_savings` | the Forecasting insight, `RecurringStore`, `LoanInfo` + `LoanWhatIf`, `SavingsProjection` |

Rules:
- **Writes only through a draft.** A draft tool returns a `draftId`; the person saves it with the
  card's button (the confirmation rule of [intents.md](intents.md) §2.1), and "Undo" removes what
  was saved. `draft_transactions` (expenses, incomes, transfers between ordinary accounts) goes
  through `makeDraft` as voice and Siri do; the `confirm` card shows the operations as they will
  stand in History, marks a guessed account or category, and saves all or nothing.
  `draft_budget` changes a category's limit (Undo restores it); `draft_recurring` creates a
  subscription or a regular payment through `SubscriptionCreationService`, the subscription
  screen's path (Undo deletes the series and what it created). An expense or income is edited on
  the card before saving: the voice form opens, `makeDraft` parses it again (`AgentDraftEditor`),
  `AgentDraftBook.replace` swaps it, and the next question tells the model in `<draft_status>`.
  `draft_debt` is Pro (without Pro Ten offers a fact instead).
- A result carries a `Decimal`, a currency and entity ids, **never** a formatted amount.
- **Other currencies** are converted to the base one with the app's rates: `_base` fields
  (`amount_base`, `balance_base`, `monthly_base`, `saved_base`, `remaining_base`) and every total.
  A rate missing from the cache is loaded first (`FinanceToolkit.loadMissingRates`); a currency
  still without one goes to `missing_rates` and stays out of the total, never counted as zero.
  `convert_currency` answers rate questions with the app's reference rate for the day
  ([currency.md](currency.md)); Ten says a bank's own buy and sell rates differ.
- Sweeps over 19k transactions run off the main actor on a snapshot (red flag 9), or use
  `TransactionStore`'s O(1) indexes. The agent keeps no caches of its own (red flag 12).
- Pro limits are checked in the tool.
- Text from statements and notes (merchant names, comments) is marked as data in results: it is a
  prompt-injection input, and writing needs a confirmation anyway.

**FastPath** (`AgentFastPath`): a message the voice parser reads as incomes or expenses (each part
with an amount and a category; no question, plan, transfer, repeat or budget in any of the 11
languages) is drafted on the phone by `makeDraft`, with no cloud and no consent. Typed, it is free;
spoken, it spends one free action. The model learns about it with the next question
(`<draft_status>`: "made on the phone"); the thread keeps its place
(`AgentThreadSnapshot.LocalExchange`).

## 4. Replies: blocks, never numbers

The model draws no interface and writes no figures. It ends a turn with the `render_reply` tool:

```swift
struct AgentReply {
    var blocks: [AgentBlock]
    var mood: AgentMood          // idle, happy, concerned, celebrate, proud, surprised, love,
                                 // playful, empty (render_reply's enum; prompt.ts says when)
    var suggestions: [String]    // follow-up questions as chips
}

enum AgentBlock {                // AgentReply.swift; source = a tool result's result_id
    case text(String)
    case metric(label: String, source: String, path: String, trendPath: String?)
    case chart(kind: AgentChartKind, title: String, source: String, path: String)
    case transactions(title: String?, source: String)
    case budgets(source: String, categoryIds: [String]?)
    case recurring(source: String)
    case forecast(source: String)
    case insight(source: String, insightId: String)
    case confirm(draftId: String)
    case open(destination: AgentDestination, targetId: String?, label: String)
    case unsupported(type: String)   // a block newer than the app
}
```

- **The model chooses what to show; every figure comes from a tool result by reference**
  (`source` = the result's `result_id`, `path` = a dotted path inside it; `AgentReplyData`). A
  made-up amount is impossible by construction, and amounts go through `FormattedAmountText`
  (red flag 7). Lists turn back into the app's own models by id.
- `render_reply` is not strict: the API compiles all strict schemas into one grammar and refuses
  the union of blocks ("compiled grammar is too large", a 400 on every request). The app decodes
  each block on its own and skips one with a missing or wrong field; the rest of the reply stays.
  The eval's `blocks_decode` check keeps models within the schema. Drafts stay strict except goals
  and debts, whose optional fields are simply left out (`tools.test.ts`).
- Text blocks are Markdown (a bold main point, "- " lists, "1. " steps, rarely "### "):
  `AgentReplyMarkdown` splits them into DesignKit's `ArticleBody` blocks.
- `AssistantReplyView` maps blocks onto the app's cards: `TransactionCardView`,
  `BudgetProgressRow`, `SubscriptionCard`, `InsightsCardView`, `MetricCard`, `CategoryBreakdownRow`,
  the charts through `PeriodChartAdapters`, drafts as `AssistantDraftCard` (on `AssistantCard` and
  `TransactionCardView`).
- `open` leads to the app's screens inside the assistant's stack (`AssistantDestinationView`): a
  category or an account by id from `<app_context>` (an account opens by kind: deposit, loan,
  ordinary), History (filtered by category when an id is given), Analytics, budgets,
  subscriptions. An id that does not exist shows an empty state, never another screen.

## 5. Threads and memory

- **Threads** live on the phone in CoreData v13 (`AgentThreadEntity`, `AgentThreadStore`, outside
  the repository facade): the whole conversation as JSON compressed with LZFSE. Compression is
  required: `payload` allows external storage, a value over ~100 KB would go to a file next to the
  database, and a backup takes only `Tenra.sqlite`. Threads from before 1.6 (27) are plain JSON and
  still read. A thread is written after each reply; the last one reopens with the assistant, its
  questions and answers replayed from the conversation (`AssistantViewModel.entries(replaying:)`);
  anything started from the assistant's home begins a new one; 20 are kept. Drafts do not come
  back after a relaunch (their cards are empty). A long history drops its oldest questions whole
  (`trimIfNeeded`: at most 60 messages and 128 KB; the server takes 80 and 256 KB) and the context
  is sent again. "Delete all data" and a restore reset the open thread and Ten's Home notices
  (`AssistantViewModel.storeDidReset`, `AssistantInbox.clear`). The assistant's home lists the open
  thread and five more; tap opens, touch and hold deletes (`deleteThread`).
- **Facts** ("salary on the 10th", "saving for a car"): the model proposes one with `draft_fact`,
  as any draft ("Ten will remember this", "Was: …" for a change, "Ten will forget this"). The same
  tool changes a fact (`replaces` with its id) and forgets one (`replaces` without text). CoreData
  v14 (`AgentFactEntity`, `AgentFactStore` under `AgentMemory`): in backups, wiped by "Delete all
  data". They reach the model as `facts you remember about the user: f1 "…"` in `<app_context>`. A
  fact is one sentence up to 200 characters, at most 30, no duplicates. The prompt forbids card and
  account numbers, PINs, passwords, codes, documents, health and other people's personal data (eval
  case `ru-no-secret-fact`).
- **Settings → Assistant** (`SettingsAssistantSection`): "Cloud answers" (the same consent the
  chat asks for; turned off, the chat asks again), "Ten chats", and "What Ten knows about me"
  (`AssistantMemoryView`: edit on tap, Forget from the touch-and-hold menu, "+" adds by hand,
  "Forget all"). The consent text names the facts among what is sent.

## 6. Ten writes first

`AssistantInbox` turns what the app already notices into notices ([insights.md](insights.md)
§Signal notifications): critical and warning insights of the pushed kinds (at most two new a day),
last week's summary once a week, subscriptions charging tomorrow, a debt due tomorrow and a goal
behind its schedule (once a month). Each has a key and never repeats. They show only on Home
(`AssistantNoticesSection`, under the accounts): the newest unread one with Ten in its mood and the
count of the rest; "Go through it" opens the assistant with a question and a `<notice>` block (one
free action), "Hide" shows the next. Works without notification permission. A push of an insight
still opens Analytics.

Auto-capture not set up (`Kind.setup`, `AssistantNotices.setupNudge`): once, after
`setupAfterEntries` entries, for someone who hid Home's auto-capture card; its button is "Set
up" and opens the Wallet guide instead of asking Ten (no action spent), and it leaves once an
automation records a payment (`Subjects.capturing`).

A notice keeps a copy of its text with the amounts as dots (`hiddenBody`), shown while "hide
amounts" is on. A notice about a subscription, a debt or a goal leaves with it: the Home section
shows only notices whose subject is still there (`AssistantNotices.Subjects`: active
subscriptions, open debts, goals, read once every store has loaded), and
`refreshAssistantInbox` drops the rest for good (their keys stay posted).

## 7. The tab, the chat, voice and attachments

- **Navigation** (owner's decisions, 2026-10-14): the tab's root is the assistant's home
  (`AssistantView`: Ten, ready questions or questions about the screen, recent chats, the
  composer); each chat is a page over it (`AssistantChatView`). The chat has only "back" and Ten
  in the middle of the navigation bar, 120 pt, on the bar's backing (`safeAreaBar`), its lower half
  over the start of the thread, which scrolls under the hard scroll edge (the owner's choice,
  [design-system.md](../design-system.md) §4); Ten stays on top (thinking, answering, mood). No
  history, "new chat" or tab bar (`TabBarVisibility`). Reply text is selectable. Ten's follow-up
  questions sit in one scrolling row above the composer.
- **Composer** (DesignKit's `MessageComposer`): the paperclip opens the attachment menu, the
  microphone (while the field is empty) opens `AssistantVoiceSheet` (`EdgeGlow`, live
  transcription in `AnimatedTranscriptionText`); what was said is sent as a message. Voice follows
  the app's language or the setting (`VoiceRecognitionLanguage`, [voice.md](voice.md)).
- **Ready questions** on the home are plain questions to the model (`AssistantView`); without the
  network or quota there is no answer, only the error with "Retry".
- **Attachments** (`AssistantAttachmentMenu`, `AssistantAttachmentSources`): a receipt from the
  scanner or Photos, a PDF or CSV statement, read on the phone by the existing pipelines, whose
  rules do not change ([import.md](import.md)): receipt `VisionDocumentExtractor` →
  `ReceiptInterpreter`; statement `DocumentImportService` → `StatementReviewPreparer` (shared with
  the import tab); CSV goes straight to its own import flow. The thread shows a summary card
  (`AssistantAttachmentCard`); "Check and save" opens `ReceiptConfirmationView` or
  `ImportTransactionPreviewView`. **Files and photos never leave the phone**: the model gets only a
  summary (`AgentAttachmentSummary.modelText`: figures, no names or shops) as an
  `<attachment_result>` block with the next question. The first open spends one free action;
  without one it offers Pro and opens after the purchase. Attachments live in memory and do not
  survive a relaunch (backlog).
- **Open in Tenra**: `CFBundleDocumentTypes` (PDF, CSV, `Alternate`),
  `LSSupportsOpeningDocumentsInPlace = NO`, `onOpenURL` → `AppCoordinator.pendingAttachment` → the
  assistant's tab (without the assistant, the import tab); the copy in `Documents/Inbox` is deleted
  after reading. A Share Extension would need an App Group, which the app does not have.

## 8. Server and protocol (`server/assistant/`)

A Cloudflare Worker (Workers Paid). It hides the Anthropic key, checks Pro through RevenueCat,
keeps quotas in KV (`tenra-assistant-quota`), **logs no content**, and has a switch
(`ASSISTANT_ENABLED`) to stop the cloud without a release. Configuration in `wrangler.toml`:
`ASSISTANT_MODEL` `claude-haiku-5-5`, `ASSISTANT_EFFORT` low, `ASSISTANT_MAX_TOKENS`,
`FREE_MONTHLY_CALLS` 150 and `PRO_MONTHLY_CALLS` 900 (per App Attest key), `GLOBAL_DAILY_CALLS`,
`BLOCKED_COUNTRIES` `RU,BY` (not in Anthropic's supported countries; Kazakhstan is), `APP_ID`.
Keys are Worker secrets. The prompt and its version are `src/prompt.ts` (`PROMPT_VERSION`);
`GET /v1/health` returns the protocol and the prompt version.

The app runs the agent loop, because the tools run on the phone: one server call is one model call.

- `POST /v1/turn`, header `x-tenra-user` (the RevenueCat app user id), body
  `{"protocol": 1, "messages": [...], "user": "<the same id>"}` in Messages API form. Pro is checked
  only for the `user` in a body signed by App Attest; a header without it counts as free, a
  mismatch is 401 `user`. The server adds its system prompt, tools, model and caching; a client
  `system` role and `cache_control` are refused.
- Body limits (`src/validate.ts`): 256 KB, 80 messages, a text block up to 16 KB (it carries
  `<app_context>`), a tool result up to 64 KB.
- Thinking blocks are bound to everything before them; a new prompt or a trimmed history makes
  them foreign, a 400 with no retry. The server sends
  `thinking.block_binding.prefix_mismatch_behavior: "drop_block"` (beta
  `thinking-binding-controls-2026-08-01`): such blocks are dropped and the turn goes on.
- Response: SSE. `tool {name}` (the "thinking" steps), `text {text}` (not shown), `reply {json}`
  (a piece of `render_reply`'s input while it is written: the tool has `eager_input_streaming`, and
  `AgentPartialReply` shows the blocks' text as it comes), `done` (`content`, `stop_reason`,
  `usage`, `tier`, `quota`), `error {code, retryable}`.
- History is append-only: the app stores `done.content` as is and sends it back unchanged (else
  thinking blocks and the cache break). A refusal (`refused`) and a truncated tool input
  (`truncated`) do not save the turn.
- A turn ends with `render_reply`; the next user message starts with a `tool_result` "shown" for
  it. `render_reply` together with other calls in one message is returned as an error
  (`AgentProtocol.renderReplyTooEarly`, the same text in the eval): their ids do not exist yet.
- The model does not see `tool_use` ids, so blocks do not reference them: the phone puts a
  `result_id` (`r1`, `r2`… per thread) into every successful result, and a block's `source` is it.
- The first message of a thread carries `<app_context>`: today's date, locale, base currency,
  accounts and categories with ids, the facts (format: `eval/fixture.ts`, `appContext`). A new one
  is sent when the date or the lists change.
- Errors before the stream: 400 `invalid`, 401 `user`, 401 `attest` (with `reason`), 429 `quota`
  or `busy`, 451 `region_unavailable` (the app shows `assistant.error.region`), 502
  `entitlement_unavailable`, 503 `disabled`.
- In the app (`AssistantFailure`): a turn refused as `invalid` (its size, its fields) is
  `tooLong`, with no Retry (resending fails the same way); 502 (RevenueCat did not answer) and
  5xx are `busy`; an `attest` refusal or a refused registration (400 `attestation` from
  `/v1/attest`) is `generic` with Retry (a new assertion or a new key), except `unsupported`
  (`unsupportedDevice`). A failure to sign (no network while registering the key) is thrown, not
  swallowed: it reads as offline, not as a permanent refusal.
- **App Attest** (`src/appattest.ts`): a turn is accepted only from the real app on a real device,
  Pro or not, and the signature is checked before RevenueCat and any KV write. Once per install:
  `GET /v1/attest/challenge` → `{challenge}` (single use, 5 minutes); the app makes a
  `DCAppAttestService` key and its attestation with `clientDataHash = SHA256(challenge)`;
  `POST /v1/attest {keyId, attestation, challenge}`. The server checks the chain to Apple's App
  Attestation root (`src/apple-root.ts`), the nonce, keyId, app id, a zero counter, the environment
  and the credential id, and keeps the public key in KV. Each turn carries `x-tenra-key` and
  `x-tenra-assertion` (a signature of the body); the counter grows and a replay is refused. Tests
  use a synthetic chain (`test/fixtures/make-appattest.mjs`). In the app `AgentAttestation`
  registers the key on the first turn (key id in UserDefaults: an App Attest key does not survive a
  reinstall), `AgentServerClient` signs every body, and `unknown_key` gets a new key and one retry.

## 9. The mascot

`ParticleCreature` (DesignKit): a dark glass sphere with some 400 particles, eyes that blink and
follow the finger, a mesh between near particles, a core glowing in the mood's colour. The mood is
`render_reply`'s `mood` (`AgentMood`) once a reply arrives, and the app's own states before it:
listening with the voice level (`AssistantVoiceSheet`), thinking while tools run, determined after
several (`AssistantView`). Gestures, speech and a wardrobe come from DesignKit
(`ParticleCreature*`; the wardrobe opens from the assistant's home). Touch parts the particles. At 22 pt (the tab) and under Reduce Motion it is a still glyph: 12 dots and the
eyes (`CreatureTabLabel`). Name: Ten (Тэн). Tone: friendly, short, no moralising or shame about
spending, no em dashes, in all 11 languages.

## 10. Privacy, consent and safety

- **Consent before the cloud** (App Review 5.1.2(i)): a screen at the first cloud question (what
  is sent, where, that nothing is stored; `assistant.consent.*` in all 11 languages), the toggle in
  Settings → Assistant. The App Privacy label lists what Ten sends (published 2026-10-18).
- **Minimisation**: the cloud gets tool results, never the database; files and photos never leave
  the phone (§7).
- **No write without a confirmation**, and Undo after saving.
- **A full finance helper with one boundary** (Anthropic's High-risk Use Case Requirements): Ten
  analyses spending, finds savings, calculates loans and savings growth, explains deposits, bonds,
  stocks, funds, ETFs, crypto, risk, fees and horizon on the person's own figures, but does not
  recommend buying, selling or holding a **specific** product, nor give personal tax advice: one
  sentence pointing to a licensed adviser, then it keeps helping. A refusal without help on a money
  question is forbidden by the prompt and caught by the eval (`no_refusal`), a product pick too
  (`noPick`). The consent screen says Ten runs on AI.
- Russia and Belarus: the server answers 451 by the request's country. Hiding the cloud mode by
  storefront is open (backlog).

## 11. Limits, Pro and cost

- **Free allowance** (`PremiumConfig.Assistant`, counted in Keychain by `AssistantUsageStore`, so
  it survives a reinstall; `AssistantAllowance`): 30 actions in the first 7 days, then 10 a month,
  reset on the 1st. An action is a spoken entry, an attachment, or a reply with analysis or a plan.
  A typed entry the phone's parser understands ("coffee 1500") is free; so are the Home notices
  (looking into one is an action) and the Analytics tab. `AssistantViewModel.Access` checks before
  sending: a question over the allowance stays in the thread with a Pro card ("Get Tenra Pro") and
  is sent after the purchase (`retry()`). A line "N left" shows above the composer at 3 or fewer.
- **The server's quota** per App Attest key (§8) sits above the app's, so a new user id does not
  reset it. A device without App Attest gets no assistant.
- **Pro**: no allowance within fair use (`PRO_MONTHLY_CALLS`), Founding Users and lifetime
  included. No separate AI subscription ([promotion-plan.md](../promotion-plan.md) §2).
- **Cost** (Anthropic prices per 1M tokens, 2026-10: Haiku 5.5 $0.10 / $0.50, Sonnet 5.5 $2 / $10,
  Opus 5.5 $4 / $20; a message ≈ 2 model calls, ~16k input tokens half cached, ~1k output): Haiku
  ≈ $0.002 a message, ≈ $0.12 for 60 a month, against ≈ $0.67 a month net of an annual Pro.
  Production runs Haiku 5.5: the same eval score as Sonnet and Opus, and the only one within the
  subscription's price. Another model is one line (`ASSISTANT_MODEL`) and a deploy. The Anthropic
  workspace has a monthly spend limit ($20; $50 with spend alerts at 50 % and 80 % while the ads
  run; at the limit Ten is silent for everyone until the next month). `GLOBAL_DAILY_CALLS` (1 200)
  keeps one day under a 30th of that limit, about $0.0014 a call, so a busy day silences Ten until
  midnight UTC rather than the limit for the month; raise the two together (calls ≈ limit × 24).

## 12. Setup, deploy and eval

- **Secrets** (GitHub → Settings → Secrets and variables → Actions): `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`, `ANTHROPIC_API_KEY` (a separate "Tenra" workspace with a spend limit),
  `REVENUECAT_SECRET_KEY`. The KV namespace id is in `wrangler.toml`. The server is at
  `https://tenra-assistant.dakacom.workers.dev`, its address in the app's Info.plist
  (`TenraAssistantURL`).
- **Workflow** `Assistant server` (`.github/workflows/assistant.yml`): typecheck and unit tests on
  every push to `server/assistant/**`; by hand, `deploy` (uploads the secrets to the Worker) or
  `eval` (models, effort, cases).
- **Pro for a person on the server**: the server sees only RevenueCat, so a Founding User (kept on
  the phone) needs `pro` granted there (Actions → RevenueCat → `grant`).
- **Eval** (`server/assistant/eval/`): a synthetic user (`fixture.ts`; never real statements), a
  tool simulator, 45 cases in Russian and English (`cases.ts`), checks: the right tool, figures
  only by reference, no amounts in text, a draft instead of "saved", the language, prompt
  injection in a note, `blocks_decode`, `no_refusal`, `noPick`. A prompt change bumps
  `PROMPT_VERSION` and runs the eval before the deploy.

## 13. Tests

- App: `TenraTests/Services/Agent/`: `AgentProtocolTests` (the wire format), `AgentConversationTests`,
  `AgentReplyDataTests` (figures by reference), `AgentDraftTests`, `AgentFastPathTests`,
  `AgentMemoryTests`, `AgentAttachmentTests`, and the tools over fixtures (`AgentCurrencyToolsTests`,
  `AgentForecastTests`, `AgentPlanningTests`).
- Server: `npm test` in `server/assistant/` (`test/`: `index`, `quota`, `entitlement`, `claude`,
  `appattest` on a synthetic chain, `tools` for the schemas, `eval` for the grader).
- Not testable here: the real App Attest flow, streaming on a device, Ten's animation; checked on
  the iPhone.
