# Supabase Logo Storage Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all bank logos from Assets.xcassets to Supabase Storage, add SupabaseLogoProvider as first in chain, remove BankLogo enum and all local logo assets.

**Architecture:** SupabaseLogoProvider fetches from `{base_url}/{domain}.png`. Chain becomes Supabase → LogoDev → GoogleFavicon → Lettermark. IconSource simplified to 2 cases: `.sfSymbol` and `.brandService`. All 30+ files referencing BankLogo updated.

**Tech Stack:** SwiftUI, URLSession, Supabase Storage (public bucket), Info.plist config

**Spec:** `Docs/superpowers/specs/2026-03-18-supabase-logo-storage-design.md`

---

## Chunk 1: SupabaseLogoProvider + Chain Update

### Task 1: Create SupabaseLogoProvider

**Files:**
- Create: `Tenra/Services/Core/SupabaseLogoProvider.swift`

- [ ] **Step 1: Create the provider**

```swift
//
//  SupabaseLogoProvider.swift
//  Tenra
//
//  Fetches logos from Supabase Storage public bucket
//

import UIKit

/// Fetches brand logos from Supabase Storage.
/// URL: {SUPABASE_LOGOS_BASE_URL}/{domain}.png
/// Returns nil if base URL not configured or logo not found.
nonisolated final class SupabaseLogoProvider: LogoProvider {
    let name = "supabase"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    /// Base URL read once from Info.plist at init time
    private static let baseURL: String? = {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let url = plist["SUPABASE_LOGOS_BASE_URL"] as? String,
              !url.isEmpty else {
            return nil
        }
        return url
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard let baseURL = Self.baseURL else { return nil }

        let urlString = "\(baseURL)/\(domain).png"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Filter out empty/error responses
            guard data.count > 100 else { return nil }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Add SUPABASE_LOGOS_BASE_URL to Info.plist**

Add key `SUPABASE_LOGOS_BASE_URL` with empty string value (user will fill in their Supabase project URL).

- [ ] **Step 3: Update LogoService chain**

In `Tenra/Services/Core/LogoService.swift`, replace the providers array:

```swift
// Old:
private let providers: [any LogoProvider] = [
    LocalLogoProvider(),
    LogoDevProvider(),
    GoogleFaviconProvider(),
    LettermarkProvider(),
]

// New:
private let providers: [any LogoProvider] = [
    SupabaseLogoProvider(),
    LogoDevProvider(),
    GoogleFaviconProvider(),
    LettermarkProvider(),
]
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Core/SupabaseLogoProvider.swift Tenra/Services/Core/LogoService.swift Tenra/Info.plist
git commit -m "feat: add SupabaseLogoProvider as first in chain

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 2: Remove BankLogo + IconSource Simplification

### Task 2: Simplify IconSource (remove .bankLogo case)

**Files:**
- Modify: `Tenra/Models/IconSource.swift`

- [ ] **Step 1: Remove .bankLogo case and all related code**

Replace entire `IconSource.swift` with:

```swift
//
//  IconSource.swift
//  Tenra
//
//  Unified icon/logo source model for all entities
//

import Foundation

/// Универсальный источник иконки/логотипа для всех сущностей
enum IconSource: Codable, Equatable, Hashable {
    case sfSymbol(String)           // SF Symbol иконка
    case brandService(String)       // Логотип бренда через provider chain

    private enum CodingKeys: String, CodingKey {
        case sfSymbol, brandService
    }
    private enum AssocCodingKeys: String, CodingKey { case _0 }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.sfSymbol) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .sfSymbol)
            self = .sfSymbol(try nested.decode(String.self, forKey: ._0))
        } else if container.contains(.brandService) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .brandService)
            self = .brandService(try nested.decode(String.self, forKey: ._0))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown IconSource case"))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sfSymbol(let name):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .sfSymbol)
            try nested.encode(name, forKey: ._0)
        case .brandService(let name):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .brandService)
            try nested.encode(name, forKey: ._0)
        }
    }

    /// Строковый идентификатор для сохранения
    var displayIdentifier: String {
        switch self {
        case .sfSymbol(let name):
            return "sf:\(name)"
        case .brandService(let name):
            return "brand:\(name)"
        }
    }

    /// Парсинг из строкового идентификатора
    static func from(displayIdentifier: String) -> IconSource? {
        if displayIdentifier.hasPrefix("sf:") {
            return .sfSymbol(String(displayIdentifier.dropFirst(3)))
        } else if displayIdentifier.hasPrefix("brand:") {
            return .brandService(String(displayIdentifier.dropFirst(6)))
        }
        return nil
    }
}
```

Note: `migrate()` method deleted entirely — no users, no migration needed.

- [ ] **Step 2: Commit (will NOT build yet — many files still reference .bankLogo)**

```bash
git add Tenra/Models/IconSource.swift
git commit -m "refactor: remove IconSource.bankLogo case, simplify to 2 cases

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Simplify ServiceLogoEntry + Delete legacy ServiceLogo enum

**Files:**
- Modify: `Tenra/Models/ServiceLogo.swift`

- [ ] **Step 1: Remove bankLogo field from ServiceLogoEntry**

In `ServiceLogo.swift`, replace `ServiceLogoEntry` struct with:

```swift
struct ServiceLogoEntry: Sendable, Identifiable {
    let domain: String
    let displayName: String
    let category: ServiceCategory
    let aliases: [String]

    nonisolated var id: String { domain }
}
```

Remove the two `init` overloads and the `iconSource` computed property.

- [ ] **Step 2: Remove bankLogo: parameter from all bank entries**

In `ServiceLogoRegistry.allServices`, remove `, bankLogo: .kaspi` etc from all 27 bank entries. They should look like:

```swift
ServiceLogoEntry(domain: "kaspi.kz", displayName: "Kaspi", category: .banks, aliases: ["каспи", "kaspi"]),
```

- [ ] **Step 3: Delete the legacy ServiceLogo enum**

Delete everything from `enum ServiceLogo: String, CaseIterable, Identifiable {` to its closing `}` (lines ~285-480). This is dead code — `ServiceLogoRegistry` replaced it.

- [ ] **Step 4: Update ServiceCategory.services() method**

Remove the legacy `services()` method that references `ServiceLogo`:

```swift
// Delete this:
func services() -> [ServiceLogo] {
    ServiceLogo.allCases.filter { $0.category == self }
}

// Keep this:
func registryServices() -> [ServiceLogoEntry] {
    ServiceLogoRegistry.services(for: self)
}
```

- [ ] **Step 5: Commit**

```bash
git add Tenra/Models/ServiceLogo.swift
git commit -m "refactor: remove ServiceLogoEntry.bankLogo field, delete legacy ServiceLogo enum

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Update IconView (remove .bankLogo branch)

**Files:**
- Modify: `Tenra/Views/Components/Icons/IconView.swift`

- [ ] **Step 1: Update convenience init**

Replace the `switch source` in convenience `init(source:size:)`:

```swift
// Old:
case .bankLogo:
    self.style = .bankLogo(size: size)

// New: remove .bankLogo case entirely. Only .sfSymbol, .brandService, .none remain.
```

New init:
```swift
init(source: IconSource?, size: CGFloat = AppIconSize.xl) {
    self.source = source
    switch source {
    case .sfSymbol:
        self.style = .categoryIcon(size: size)
    case .brandService:
        self.style = .serviceLogo(size: size)
    case .none:
        self.style = .placeholder(size: size)
    }
}
```

- [ ] **Step 2: Update contentView switch**

Remove `.bankLogo` case:

```swift
@ViewBuilder
private var contentView: some View {
    switch source {
    case .sfSymbol(let name):
        sfSymbolView(name)
    case .brandService(let name):
        brandServiceView(name)
    case .none:
        placeholderView
    }
}
```

- [ ] **Step 3: Delete bankLogoView method entirely**

Delete the entire `bankLogoView(_ logo: BankLogo)` method (lines ~214-225).

- [ ] **Step 4: Update effectivePadding and shouldClipContentForSource**

Replace `.bankLogo, .brandService` with just `.brandService`:

```swift
// effectivePadding:
case .brandService:
    return nil

// shouldClipContentForSource:
case .brandService:
    return true
```

- [ ] **Step 5: Update doc comments**

Remove the bank logo example from the top-level doc comment (lines ~22-24).

- [ ] **Step 6: Commit**

```bash
git add Tenra/Views/Components/Icons/IconView.swift
git commit -m "refactor: remove .bankLogo branch from IconView

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Update IconStyle + UniversalRow + component views

**Files:**
- Modify: `Tenra/Models/IconStyle.swift`
- Modify: `Tenra/Views/Components/Rows/UniversalRow.swift`
- Modify: `Tenra/Views/Components/Icons/StaticSubscriptionIconsView.swift`
- Modify: `Tenra/Views/Components/Cards/LoansCardView.swift`
- Modify: `Tenra/Views/Components/Forms/LoanPayAllView.swift`
- Modify: `Tenra/Views/Components/Icons/IconPickerView.swift`

- [ ] **Step 1: Rename IconStyle factory methods**

In `IconStyle.swift`, rename:
- `static func bankLogo(size:)` → `static func roundedLogo(size:)`
- `static func bankLogoLarge(size:)` → `static func roundedLogoLarge(size:)`

Update the doc comments to remove "банковский" references.

- [ ] **Step 2: Remove UniversalRow.IconConfig.bankLogo method**

In `UniversalRow.swift`, delete the `bankLogo(_ logo: BankLogo, size:)` static method (lines ~142-154). Remove any preview code using `.bankLogo`.

- [ ] **Step 3: Update StaticSubscriptionIconsView**

Replace `.bankLogo, .brandService, .none:` with `.brandService, .none:`:

```swift
private var iconStyle: IconStyle {
    switch subscription.iconSource {
    case .sfSymbol:
        return .circle(size: size, tint: .accentMonochrome, backgroundColor: AppColors.surface)
    case .brandService, .none:
        return .circle(size: size, tint: .original)
    }
}
```

- [ ] **Step 4: Update LoansCardView**

Same pattern — replace `.bankLogo, .brandService, .none:` with `.brandService, .none:`.

- [ ] **Step 5: Update LoanPayAllView**

Replace `.bankLogo(size:)` with `.roundedLogo(size:)`:

```swift
leadingIcon: .custom(source: loan.iconSource, style: .roundedLogo(size: AppIconSize.lg))
```

- [ ] **Step 6: Update IconPickerView — remove LogoItem.bank case**

In `IconPickerView.swift`, simplify `LogoItem` enum:

```swift
private enum LogoItem: Identifiable {
    case service(ServiceLogoEntry)

    var id: String { "service_\(entry.domain)" }

    var entry: ServiceLogoEntry {
        switch self {
        case .service(let entry): return entry
        }
    }

    var iconSource: IconSource {
        .brandService(entry.domain)
    }
}
```

Note: `LogoItem` is now trivially a wrapper but kept for compatibility with `LogoCategorySection`.

- [ ] **Step 7: Commit**

```bash
git add Tenra/Models/IconStyle.swift \
  Tenra/Views/Components/Rows/UniversalRow.swift \
  Tenra/Views/Components/Icons/StaticSubscriptionIconsView.swift \
  Tenra/Views/Components/Cards/LoansCardView.swift \
  Tenra/Views/Components/Forms/LoanPayAllView.swift \
  Tenra/Views/Components/Icons/IconPickerView.swift
git commit -m "refactor: rename bankLogo styles, remove .bankLogo from component views

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 3: CoreData + Repository Cleanup

### Task 6: Clean CoreData entities and repositories

**Files:**
- Modify: `Tenra/CoreData/Entities/AccountEntity+CoreDataClass.swift`
- Modify: `Tenra/CoreData/Entities/RecurringSeriesEntity+CoreDataClass.swift`
- Modify: `Tenra/Services/Repository/AccountRepository.swift`
- Modify: `Tenra/Services/Repository/RecurringRepository.swift`
- Modify: `Tenra/Models/Transaction.swift`
- Modify: `Tenra/Models/RecurringTransaction.swift`

- [ ] **Step 1: Update AccountEntity+CoreDataClass.swift**

Replace the BankLogo fallback (lines ~28-30):

```swift
// Old:
} else if let logoString = logo, let bankLogo = BankLogo(rawValue: logoString), bankLogo != .none {
    iconSource = .bankLogo(bankLogo)

// New: remove this else-if block entirely. Just:
} else {
    iconSource = nil
}
```

- [ ] **Step 2: Update RecurringSeriesEntity+CoreDataClass.swift**

Replace the BankLogo reconstruction (lines ~31-32):

```swift
// Old:
if let logoString = brandLogo, let bankLogo = BankLogo(rawValue: logoString), bankLogo != .none {
    iconSource = .bankLogo(bankLogo)
} else if let brandId = brandId, !brandId.isEmpty {

// New:
if let brandId = brandId, !brandId.isEmpty {
    iconSource = IconSource.from(displayIdentifier: brandId) ?? .brandService(brandId)
} else {
    iconSource = nil
}
```

- [ ] **Step 3: Update AccountRepository.swift**

Replace the `.bankLogo` write path (lines ~221-225):

```swift
// Old:
if case .bankLogo(let bankLogo) = account.iconSource {
    existing.logo = bankLogo.rawValue
} else {
    existing.logo = BankLogo.none.rawValue
}

// New:
existing.logo = nil
```

- [ ] **Step 4: Update RecurringRepository.swift**

Replace the `.bankLogo` case (lines ~284-286):

```swift
// Old:
case .bankLogo(let bankLogo):
    entity.brandLogo = bankLogo.rawValue
    entity.brandId = nil

// New: remove this case. Only .sfSymbol and .brandService remain:
case .sfSymbol(let name):
    entity.brandLogo = nil
    entity.brandId = "sf:\(name)"
case .brandService(let brandId):
    entity.brandLogo = nil
    entity.brandId = brandId
```

- [ ] **Step 5: Update Transaction.swift**

Remove the BankLogo fallback decoder (lines ~484-485):

```swift
// Old:
} else if let oldBankLogo = try container.decodeIfPresent(BankLogo.self, forKey: .bankLogo) {
    iconSource = oldBankLogo != .none ? .bankLogo(oldBankLogo) : nil

// New: remove this else-if. Just:
} else {
    iconSource = nil
}
```

Also update the comment on line ~445 from `(SF Symbol, BankLogo, logo.dev)` to `(SF Symbol, brand service)`.

- [ ] **Step 6: Update RecurringTransaction.swift**

Remove the BankLogo migration in Codable decoder (line ~119):

```swift
// Old:
let oldBrandLogo = try container.decodeIfPresent(BankLogo.self, forKey: .brandLogo)
let oldBrandId = try container.decodeIfPresent(String.self, forKey: .brandId)
iconSource = IconSource.migrate(bankLogo: oldBrandLogo, brandId: oldBrandId, brandName: nil)

// New:
if let oldBrandId = try container.decodeIfPresent(String.self, forKey: .brandId), !oldBrandId.isEmpty {
    iconSource = IconSource.from(displayIdentifier: oldBrandId) ?? .brandService(oldBrandId)
} else {
    iconSource = nil
}
```

- [ ] **Step 7: Commit**

```bash
git add Tenra/CoreData/Entities/AccountEntity+CoreDataClass.swift \
  Tenra/CoreData/Entities/RecurringSeriesEntity+CoreDataClass.swift \
  Tenra/Services/Repository/AccountRepository.swift \
  Tenra/Services/Repository/RecurringRepository.swift \
  Tenra/Models/Transaction.swift \
  Tenra/Models/RecurringTransaction.swift
git commit -m "refactor: remove BankLogo from CoreData entities and repositories

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 4: Delete Files + Assets + Preview Cleanup

### Task 7: Delete files and assets

**Files:**
- Delete: `Tenra/Services/Core/LocalLogoProvider.swift`
- Delete: `Tenra/Utils/BankLogo.swift`
- Delete: `Tenra/Utils/BrandLogoDisplayHelper.swift`
- Delete: All bank imagesets from `Assets.xcassets`

- [ ] **Step 1: Delete the 3 Swift files**

```bash
rm Tenra/Services/Core/LocalLogoProvider.swift
rm Tenra/Utils/BankLogo.swift
rm Tenra/Utils/BrandLogoDisplayHelper.swift
```

- [ ] **Step 2: Delete all bank imagesets from Assets**

```bash
# Delete all bank logo imagesets (44 directories)
cd Tenra/Assets.xcassets
# List to confirm:
ls -d *.imageset | head -50
# Delete all imagesets (they are ALL bank logos — the only non-imageset items are AccentColor.colorset and AppIcon.appiconset)
find . -name "*.imageset" -type d -exec rm -rf {} + 2>/dev/null
```

**IMPORTANT:** Verify that only imagesets are deleted, NOT `AccentColor.colorset` or `AppIcon.appiconset`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "delete: remove BankLogo.swift, LocalLogoProvider.swift, BrandLogoDisplayHelper.swift, 44 bank imagesets

-1.3 MB from app bundle. Logos now served from Supabase Storage.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Fix all preview code

**Files (16 files with preview-only BankLogo references):**
- `Views/Components/Icons/IconView+Previews.swift`
- `Views/Components/Cards/TransactionCard.swift`
- `Views/Components/Cards/TransactionCardComponents.swift`
- `Views/Transactions/TransactionEditView.swift`
- `Views/Accounts/AccountsManagementView.swift`
- `Views/Accounts/AccountEditView.swift`
- `Views/Deposits/DepositEditView.swift`
- `Views/Loans/LoanEditView.swift`
- `Views/Components/Forms/LoanPaymentView.swift`
- `Views/Components/Forms/LoanRateChangeView.swift`
- `Views/Components/Forms/LoanEarlyRepaymentView.swift`
- `Views/Components/Forms/DepositRateChangeView.swift`
- `Views/Components/Forms/EditableHeroSection.swift`
- `Views/Components/Headers/HeroSection.swift`
- `Views/Components/Input/AccountsCarousel.swift`
- `Views/Components/Rows/UniversalRow.swift` (preview section)

- [ ] **Step 1: Global find-and-replace in all preview code**

For each file, replace all occurrences of:
- `.bankLogo(.kaspi)` → `.brandService("kaspi.kz")`
- `.bankLogo(.halykBank)` → `.brandService("halykbank.kz")`
- `.bankLogo(.forte)` → `.brandService("forte.kz")`
- `.bankLogo(.homeCredit)` → `.brandService("homecredit.kz")`
- `.bankLogo(.eurasian)` → `.brandService("eubank.kz")`
- `.bankLogo(.freedom)` → `.brandService("ffin.kz")`
- `.bankLogo(.sber)` → `.brandService("sberbank.kz")`
- Any other `.bankLogo(.<case>)` → `.brandService("<domain>")`

Also replace `.bankLogo(size:)` style references with `.roundedLogo(size:)`.

Also update `IconView+Previews.swift` which may have direct `BankLogo` type references — replace with `.brandService` equivalents.

Also fix `UniversalRow.swift` preview section — replace `.bankLogo(.kaspi)` with `.brandService("kaspi.kz")` and `.bankLogo(...)` IconConfig calls with `.custom(source: .brandService("kaspi.kz"), style: .roundedLogo())`.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "fix: replace .bankLogo with .brandService in all preview code

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Build verification + final cleanup

- [ ] **Step 1: Full build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 2: Grep for any remaining BankLogo references**

```bash
grep -rn "BankLogo" Tenra/ --include="*.swift" | head -30
grep -rn "\.bankLogo" Tenra/ --include="*.swift" | head -30
grep -rn "bankLogoView" Tenra/ --include="*.swift" | head -30
```

All should return 0 results. Fix any stragglers.

- [ ] **Step 3: Grep for stale bankLogo style references**

```bash
grep -rn "\.bankLogo(" Tenra/ --include="*.swift" | head -30
```

Should return 0. If `IconStyle` still has old names, fix.

- [ ] **Step 4: Check warnings in new code**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "warning:" | grep -iE "(Supabase|bankLogo|BankLogo|LocalLogo|BrandLogoDisplay)" | head -20
```

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "chore: final cleanup after BankLogo removal

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Summary

| Task | What | Key Files |
|------|------|-----------|
| 1 | SupabaseLogoProvider + chain update | Services/Core/SupabaseLogoProvider.swift, LogoService.swift |
| 2 | IconSource simplification (2 cases) | Models/IconSource.swift |
| 3 | ServiceLogoEntry cleanup + delete legacy enum | Models/ServiceLogo.swift |
| 4 | IconView remove .bankLogo branch | Views/Components/Icons/IconView.swift |
| 5 | IconStyle rename + component views cleanup | IconStyle, UniversalRow, LoansCardView, etc. |
| 6 | CoreData + repository BankLogo removal | AccountEntity, RecurringSeriesEntity, repos |
| 7 | Delete files + assets (-1.3 MB) | BankLogo.swift, LocalLogoProvider.swift, 44 imagesets |
| 8 | Fix 16 preview files | All preview code with .bankLogo |
| 9 | Build verification + final grep | All |
