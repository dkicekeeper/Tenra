# External Integrations

**Analysis Date:** 2026-03-02

## APIs & External Services

**Exchange Rates:**
- National Bank of Kazakhstan
  - URL: `https://nationalbank.kz/rss/get_rates.cfm?fdate=DD.MM.YYYY`
  - Purpose: Fetch current and historical exchange rates for multi-currency accounts
  - Format: XML feed parsed by `ExchangeRateParserDelegate`
  - SDK/Client: URLSession (native, no wrapper)
  - Auth: None (public API)
  - Implementation: `CurrencyConverter` (Services/Utilities/CurrencyConverter.swift)
  - Cache: 24-hour in-process cache for current rates; per-date historical cache
  - Usage: Cross-currency balance calculations, transaction conversion on import

**Brand Logos:**
- Logo.dev
  - URL: `https://img.logo.dev/{brandName}?token={LOGO_DEV_PUBLIC_KEY}`
  - Purpose: Fetch brand logos for subscription/recurring transaction display
  - SDK/Client: URLSession (native)
  - Auth: `LOGO_DEV_PUBLIC_KEY` (public key in Info.plist)
  - Implementation: `LogoService` (Services/Core/LogoService.swift)
  - Cache: NSCache (200 images, 50 MB) + disk cache via `LogoDiskCache`
  - Fallback: System SF Symbol or custom icon if brand logo unavailable
  - Helper: `BrandLogoDisplayHelper` (Utils/BrandLogoDisplayHelper.swift) for source resolution

## Data Storage

**Databases:**
- CoreData with SQLite backend
  - Location: `AIFinanceManager.xcdatamodeld`
  - Persistence: SQLite file in app's Documents directory
  - Schema versions: 3 (v1, v2, v3 with no active migrations required)
  - Entities:
    - `TransactionEntity` - All transactions (income, expense, internal transfer, deposits)
    - `AccountEntity` - Bank accounts, credit cards, deposits
    - `CustomCategoryEntity` - User-defined spending categories with budget tracking
    - `RecurringSeriesEntity` - Recurring transaction series (subscriptions, repeating expenses)
    - `DepositEntity` - Deposit accounts with interest calculation
    - `MonthlyAggregateEntity` - Legacy (Phase 40 cleanup: not actively read/written)
    - `CategoryAggregateEntity` - Legacy (Phase 40 cleanup: not actively read/written)
  - Client: CoreData NSManagedObjectContext via repositories
  - Thread safety: `@unchecked Sendable` with NSLock for singleton initialization

**Fallback Storage:**
- UserDefaults
  - Keys: `storageKeyTransactions`, `storageKeyAccounts`, `storageKeyCustomCategories`, `storageKeyRecurring`, `storageKeyDeposits`
  - Format: JSON encoded arrays
  - Purpose: When CoreData is unavailable, app continues with limited persistence
  - Impl: `UserDefaultsRepository` (Services/Core/UserDefaultsRepository.swift)

**File Storage:**
- Local file system only (no cloud sync)
  - Bank statement PDFs imported via DocumentPickerViewController
  - CSV files imported via file picker or email attachments
  - Logo cache: disk storage at `LogoDiskCache` location
  - User wallpaper images via PhotosUI

**Caching:**
- In-memory: `UnifiedTransactionCache`, `NSCache` for logos
- Disk: `LogoDiskCache` for brand logos

## Authentication & Identity

**Auth Provider:**
- None - Local-only app
- No user accounts, no login required
- All data stored locally on device

**Security:**
- UserDefaults fallback only used when CoreData fails (graceful degradation)
- No network authentication or API keys sent in requests (except Logo.dev token which is public key)
- PDF and CSV imports via native file pickers (sandbox-aware)

## Document Processing

**PDF Extraction:**
- Framework: PDFKit + Vision
- Service: `PDFService` (Services/Import/PDFService.swift)
- Capabilities:
  - Text extraction from multi-page PDFs
  - Table structure detection (experimental)
  - OCR via Vision framework (`@preconcurrency import`)
  - Progress callbacks for long operations
- Usage: Import bank statements for transaction parsing

**Statement Text Parsing:**
- Service: `StatementTextParser` (Services/Import/StatementTextParser.swift)
- Purpose: Extract transaction details from unstructured bank statement text
- Patterns: Bank-specific statement format detection
- Output: Structured transaction data for import

## Voice & Speech

**Voice Input:**
- Framework: Speech (SFSpeechRecognizer), AVFoundation
- Language: Russian (ru-RU locale)
- Service: `VoiceInputService` (Services/Voice/VoiceInputService.swift)
- Features:
  - Real-time speech recognition
  - Voice Activity Detection (VAD) via `SilenceDetector`
  - Dynamic category/account context injection
  - Automatic stop on silence detection (configurable)
- Permissions: NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription
- Output: Transcribed text → parsed into transaction details

**Audio Processing:**
- Framework: AVFAudio
- Service: `SilenceDetector` (Services/Audio/SilenceDetector.swift)
- Purpose: Detect silence for automatic stop of voice input

## CSV Import/Export

**CSV Import:**
- Service: `CSVImporter` (Services/CSV/CSVImporter.swift)
- Parsing: `CSVParsingService` (Services/CSV/CSVParsingService.swift)
- Validation: `CSVValidationService` (Services/CSV/CSVValidationService.swift)
- Features:
  - Flexible column mapping (reordering, skipping)
  - Batch insert optimization via `NSBatchInsertRequest`
  - Error recovery: individual transaction fallback if batch fails
  - Account/category auto-resolution (case-insensitive)
  - Import cache via `ImportCacheManager`
- Coordination: `CSVImportCoordinator` (Services/CSV/CSVImportCoordinator.swift)
- Output: TransactionStore.addBatch() → CoreData persistence

**CSV Export:**
- Service: `CSVExporter` (Services/CSV/CSVExporter.swift)
- Format: CSV with headers
- Output: File for email/sharing via `ExportCoordinator` (Services/Settings/)

## Machine Learning

**Category Prediction:**
- Framework: CoreML
- Service: `CategoryMLPredictor` (Services/ML/CategoryMLPredictor.swift)
- Status: Stub (model not yet integrated)
- Future: Train on user's transaction history to auto-categorize imports
- Fallback: Rule-based parsing until ML model available

**Training Data Export:**
- Service: `MLDataExporter` (Services/ML/MLDataExporter.swift)
- Purpose: Prepare transaction history for Create ML model training

## Notifications

**Local Notifications:**
- Framework: UserNotifications
- Purpose: Subscription/recurring payment reminders
- Triggered: Before due date of recurring transactions
- Permissions: NSUserNotificationUsageDescription

## Webhooks & Callbacks

**Incoming:**
- None (local-only app)

**Outgoing:**
- None

## Environment Configuration

**Required env vars:**
- None - All config via Info.plist keys

**Configuration Keys (Info.plist):**
- `LOGO_DEV_PUBLIC_KEY` - Logo.dev public API token (required for brand logo fetching)

**Secrets location:**
- Info.plist (for public keys only; no private secrets stored)

## Data Import Pipelines

**Bank Statements (PDF):**
1. DocumentPickerViewController → select PDF
2. PDFService.extractText() → text + structure detection
3. StatementTextParser.parse() → transaction array
4. TransactionStore.addBatch() → CoreData + computed balances

**CSV Files:**
1. DocumentPickerViewController or email attachment → file path
2. CSVParsingService.parse() → field mapping + rows
3. CSVValidationService.validate() → row-level checks
4. CSVImportCoordinator.importTransactions() → account/category resolution
5. TransactionStore.addBatch() → NSBatchInsertRequest → CoreData

**Voice Input:**
1. VoiceInputService.startRecording() → audio buffer
2. SFSpeechRecognitionTask → real-time transcription
3. Voice parsing logic → extract amount, category, description
4. TransactionStore.add() → single transaction to CoreData

**Recurring Transactions:**
1. ManuallyCreated or ImportedFromStatement
2. RecurringTransactionService.generateOccurrences() → future transaction dates
3. TransactionStore (delegates to RecurringRepository) → persist series + occurrences
4. Background task generates future occurrences before due date

## Cross-Cutting Integrations

**Currency Conversion:**
- `TransactionCurrencyService` (display-layer cache, no network)
- `CurrencyConverter` (live rates from National Bank)
- Applied at: Transaction import (convertedAmount field set), balance calculation (cross-currency sums)

**Category Resolution:**
- `EntityMappingService` - Case-insensitive lookup of categories/accounts
- `ImportCacheManager` - Memoize lookups during CSV batch import
- Applied at: CSV/PDF import, voice parsing

**Logo Resolution:**
- `BrandLogoDisplayHelper` - Priority: SF Symbol prefix > custom icon > bank logo > brand service
- `LogoService` - Fetch and cache from logo.dev
- Applied at: Subscription display, recurring transaction cards

---

*Integration audit: 2026-03-02*
