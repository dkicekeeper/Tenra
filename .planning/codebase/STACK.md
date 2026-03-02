# Technology Stack

**Analysis Date:** 2026-03-02

## Languages

**Primary:**
- Swift 5.0 (project setting) - All application code
- Swift 6 patterns enforced via `SWIFT_STRICT_CONCURRENCY = targeted`

**Secondary:**
- XML - Exchange rate parsing (National Bank of Kazakhstan API response)

## Runtime

**Environment:**
- iOS 26.0+ (requires Xcode 26+ beta)
- Physical device: `name:Dkicekeeper 17`
- Simulator: iPhone 17 Pro (iOS 26.2), iPhone Air, iPhone 16e

**Package Manager:**
- Xcode native (no external package manager)
- No external package dependencies detected

## Frameworks

**UI & Layout:**
- SwiftUI (iOS 26+ with Liquid Glass adoption)
- Charts (charting library for insights visualizations)
- UIKit (underlying graphics, image handling)
- PhotosUI (image picker support)

**Core Data & Persistence:**
- CoreData (primary persistence layer with SQLite backend)
- UserDefaults (fallback when CoreData unavailable; stored as UserDefaultsRepository)
- Foundation (JSON encoding/decoding)

**System Frameworks:**
- Observation framework (@Observable) - Reactive UI state management
- Combine (legacy support for some services)

**Audio & Voice:**
- Speech (speech recognition for voice input transactions)
- AVFoundation (audio engine infrastructure)
- AVFAudio (low-level audio I/O)

**Document & Data Processing:**
- PDFKit (PDF extraction for bank statements)
- Vision (@preconcurrency import for OCR-related services)
- UniformTypeIdentifiers (file type identification)

**Machine Learning:**
- CoreML (category prediction model support; currently stub/future enhancement)

**Utilities:**
- Foundation (JSON, XML, date/time, collections)
- UIKit (colors, images, device info)
- QuartzCore (Core Animation, layer rendering)
- CoreGraphics (graphics drawing)
- ImageIO (image data manipulation)
- os / os.log - Unified logging throughout app

**Notifications & Scheduling:**
- UserNotifications (push/local notification support)

## Key Dependencies

**Critical:**
- SwiftUI + Observation - Entire UI framework and reactive state
- CoreData - All transaction, account, category, recurring data storage (~7.6 MB for 19k transactions in memory)
- Charts - Financial insight visualizations and analytics displays

**Infrastructure:**
- PDFKit + Vision - Bank statement PDF import and text extraction
- Speech + AVFoundation - Voice transaction input
- CoreML - Category prediction (future-ready; model not yet integrated)
- CurrencyConverter - Exchange rate fetching from National Bank of Kazakhstan

## Configuration

**Environment:**
- `Info.plist` - App manifest with permissions and API configuration
  - `LOGO_DEV_PUBLIC_KEY` - Logo.dev public API key for brand logo fetching
  - `CFBundleLocalizations` - en, ru (English and Russian support)
  - `NSDocumentPickerUsageDescription` - Bank statement file access
  - `NSMicrophoneUsageDescription` - Voice recording
  - `NSSpeechRecognitionUsageDescription` - Speech-to-text
  - `NSUserNotificationUsageDescription` - Subscription reminder notifications

**Build:**
- Xcode project format (`.xcodeproj`)
- File system synchronized root groups (Xcode 15+)
- Inter variable font TTF files embedded (`Inter-VariableFont_opsz,wght.ttf`, `Inter-Italic-VariableFont_opsz,wght.ttf`)

## Platform Requirements

**Development:**
- macOS with Xcode 26+ beta
- iOS 26.0 SDK minimum

**Production:**
- iOS 26.0+
- Requires: microphone access, document picker, speech recognition permissions
- Optional: notification permissions for subscription reminders

## Data Persistence Strategy

**Primary: CoreData**
- Location: `AIFinanceManager.xcdatamodeld` with 3 schema versions (`AIFinanceManager v3.xcdatamodel`)
- Entities: TransactionEntity, AccountEntity, CustomCategoryEntity, RecurringSeriesEntity, DepositEntity (and related aggregate entities)
- Features:
  - One-to-many relationships (Account → Transactions, Category → Transactions)
  - Inverse relationships for efficient traversal
  - Pre-aggregated caching entities (legacy, not actively used as of Phase 40)
  - JSON serialization for complex types (IconSource, category properties)

**Fallback: UserDefaults**
- Implementation: `UserDefaultsRepository` (Services/Core/)
- Purpose: When CoreData initialization fails, app can still function with limited persistence
- Storage keys: `storageKeyTransactions`, `storageKeyAccounts`, `storageKeyCustomCategories`, etc.
- Limitation: No incremental updates, less efficient for large datasets

**In-Memory Caching:**
- `TransactionStore` (ViewModels/TransactionStore.swift) - Single source of truth for transaction/account/category state
- `UnifiedTransactionCache` (Services/Cache/) - LRU cache for frequently queried transactions
- `LogoService` - 200-image NSCache for brand logos + disk cache

## External Service Integration Points

**API: National Bank of Kazakhstan (Exchange Rates)**
- URL: `https://nationalbank.kz/rss/get_rates.cfm`
- Purpose: Live and historical exchange rate fetching
- Parser: `ExchangeRateParserDelegate` (XML parsing)
- Cache: 24-hour in-process cache, plus date-specific historical cache
- Service: `CurrencyConverter` (Services/Utilities/CurrencyConverter.swift)

**API: Logo.dev (Brand Logos)**
- URL: `https://img.logo.dev/{brandName}?token={LOGO_DEV_PUBLIC_KEY}`
- Purpose: Fetch brand logos for subscriptions and recurring transactions
- Configuration: `LOGO_DEV_PUBLIC_KEY` from Info.plist
- Cache: Memory cache (200 images, 50 MB) + disk cache
- Service: `LogoService` (Services/Core/LogoService.swift)

---

*Stack analysis: 2026-03-02*
