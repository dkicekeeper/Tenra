# Logo Provider Chain Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single-source logo.dev loading with a waterfall chain (Local → LogoDev → Google Favicon → Lettermark) and add fuzzy name search for KZ/CIS brands.

**Architecture:** `LogoProvider` nonisolated protocol with 4 conforming providers. `ServiceLogoRegistry` replaces enum with struct-based lookup (domainMap + aliasMap). `LogoService` orchestrates the chain. `BrandLogoView` simplified to chain-only. `IconPickerView` gets two-phase search.

**Tech Stack:** SwiftUI, UIKit (UIGraphicsImageRenderer), URLSession, NSCache, CoreData (unchanged)

**Spec:** `Docs/superpowers/specs/2026-03-18-logo-provider-chain-design.md`

---

## Chunk 1: Provider Protocol + Implementations

### Task 1: Create LogoProvider Protocol

**Files:**
- Create: `Tenra/Services/Core/LogoProvider.swift`

- [ ] **Step 1: Create the protocol and chain runner**

```swift
//
//  LogoProvider.swift
//  Tenra
//
//  Waterfall chain protocol for logo fetching
//

import UIKit

/// Protocol for logo providers in the waterfall chain.
/// All conformances must be nonisolated (opt out of implicit MainActor).
nonisolated protocol LogoProvider {
    var name: String { get }
    func fetchLogo(domain: String, size: CGFloat) async -> UIImage?
}

/// Runs providers in order, returns first non-nil result.
nonisolated enum LogoProviderChain {
    static func fetch(
        domain: String,
        size: CGFloat,
        providers: [any LogoProvider]
    ) async -> UIImage? {
        for provider in providers {
            if let image = await provider.fetchLogo(domain: domain, size: size) {
                return image
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Add to Xcode project and verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors (or only pre-existing ones)

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/LogoProvider.swift
git commit -m "feat: add LogoProvider protocol and chain runner"
```

---

### Task 2: Create LocalLogoProvider

**Files:**
- Create: `Tenra/Services/Core/LocalLogoProvider.swift`

- [ ] **Step 1: Implement LocalLogoProvider**

This provider checks `BankLogo` assets. `BankLogo` has a `rawValue` (asset filename) and maps to local PNG in Assets.xcassets.

```swift
//
//  LocalLogoProvider.swift
//  Tenra
//
//  Checks BankLogo assets for local logo matches
//

import UIKit

/// Checks local BankLogo assets for matching domain.
nonisolated final class LocalLogoProvider: LogoProvider {
    let name = "local"

    // Pre-built domain → BankLogo mapping
    private static let domainMap: [String: BankLogo] = {
        // Map known bank domains to BankLogo cases
        // BankLogo.rawValue is the asset filename, not a domain
        let mappings: [(String, BankLogo)] = [
            ("kaspi.kz", .kaspi),
            ("halykbank.kz", .halykBank),
            ("homecredit.kz", .homeCredit),
            ("eubank.kz", .eurasian),
            ("forte.kz", .forte),
            ("jusan.kz", .jusan),
            ("hcsbk.kz", .otbasy),
            ("bcc.kz", .centerCredit),
            ("berekebank.kz", .bereke),
            ("alfabank.kz", .alfaBank),
            ("ffin.kz", .freedom),
            ("sberbank.kz", .sber),
            ("vtb.kz", .vtb),
            ("tbank.kz", .tbank),
            ("rbk.kz", .rbk),
            ("nurbank.kz", .nurBank),
            ("asiacreditbank.kz", .asiaCredit),
            ("tengribank.kz", .tengri),
            ("kdb.kz", .brk),
            ("citibank.kz", .citi),
            ("bank-china.kz", .bankOfChina),
            ("icbc.kz", .icbc),
            ("shinhan.kz", .shinhan),
            ("atfbank.kz", .atf),
        ]
        return Dictionary(uniqueKeysWithValues: mappings)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard let bankLogo = Self.domainMap[domain.lowercased()] else {
            return nil
        }
        // Load from Assets bundle (BankLogo.rawValue is the asset name)
        return UIImage(named: bankLogo.rawValue)
    }
}
```

- [ ] **Step 2: Add to Xcode project and verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/LocalLogoProvider.swift
git commit -m "feat: add LocalLogoProvider for BankLogo asset lookup"
```

---

### Task 3: Create GoogleFaviconProvider

**Files:**
- Create: `Tenra/Services/Core/GoogleFaviconProvider.swift`

- [ ] **Step 1: Implement GoogleFaviconProvider**

```swift
//
//  GoogleFaviconProvider.swift
//  Tenra
//
//  Fetches favicons from Google's favicon service
//

import UIKit

/// Fetches brand favicons from Google's public favicon API.
/// Returns nil if response is too small (<1KB) or image is ≤16x16.
nonisolated final class GoogleFaviconProvider: LogoProvider {
    let name = "googleFavicon"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")!
        components.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "sz", value: "128"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Filter out tiny/default responses
            guard data.count >= 1024 else { return nil }

            guard let image = UIImage(data: data) else { return nil }

            // Google returns 16x16 for unknown domains even with sz=128
            guard image.size.width > 16 && image.size.height > 16 else {
                return nil
            }

            return image
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project and verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/GoogleFaviconProvider.swift
git commit -m "feat: add GoogleFaviconProvider with size validation"
```

---

### Task 4: Create LettermarkProvider

**Files:**
- Create: `Tenra/Services/Core/LettermarkProvider.swift`

**Context:** Uses `CategoryColors.palette` for deterministic background color. The palette is an array of 14 `Color` values. We need to convert to `UIColor` since we render with `UIGraphicsImageRenderer`.

- [ ] **Step 1: Implement LettermarkProvider**

```swift
//
//  LettermarkProvider.swift
//  Tenra
//
//  Generates lettermark icons with deterministic colors
//

import UIKit

/// Generates a lettermark image (1-2 letters on colored background).
/// Always succeeds — this is the final fallback in the chain.
nonisolated final class LettermarkProvider: LogoProvider {
    let name = "lettermark"

    // 14 colors matching CategoryColors palette
    private static let palette: [UIColor] = [
        UIColor(red: 0x3b/255.0, green: 0x82/255.0, blue: 0xf6/255.0, alpha: 1), // blue
        UIColor(red: 0x8b/255.0, green: 0x5c/255.0, blue: 0xf6/255.0, alpha: 1), // violet
        UIColor(red: 0xec/255.0, green: 0x48/255.0, blue: 0x99/255.0, alpha: 1), // pink
        UIColor(red: 0xf9/255.0, green: 0x73/255.0, blue: 0x16/255.0, alpha: 1), // orange
        UIColor(red: 0xea/255.0, green: 0xb3/255.0, blue: 0x08/255.0, alpha: 1), // yellow
        UIColor(red: 0x22/255.0, green: 0xc5/255.0, blue: 0x5e/255.0, alpha: 1), // green
        UIColor(red: 0x14/255.0, green: 0xb8/255.0, blue: 0xa6/255.0, alpha: 1), // teal
        UIColor(red: 0x06/255.0, green: 0xb6/255.0, blue: 0xd4/255.0, alpha: 1), // cyan
        UIColor(red: 0x63/255.0, green: 0x66/255.0, blue: 0xf1/255.0, alpha: 1), // indigo
        UIColor(red: 0xd9/255.0, green: 0x46/255.0, blue: 0xef/255.0, alpha: 1), // fuchsia
        UIColor(red: 0xf4/255.0, green: 0x3f/255.0, blue: 0x5e/255.0, alpha: 1), // rose
        UIColor(red: 0xa8/255.0, green: 0x55/255.0, blue: 0xf7/255.0, alpha: 1), // purple
        UIColor(red: 0x10/255.0, green: 0xb9/255.0, blue: 0x81/255.0, alpha: 1), // emerald
        UIColor(red: 0xf5/255.0, green: 0x9e/255.0, blue: 0x0b/255.0, alpha: 1), // amber
    ]

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        let letters = Self.extractLetters(from: domain)
        let color = Self.deterministicColor(for: domain)
        return Self.renderLettermark(letters: letters, color: color, size: size)
    }

    /// Extract 1-2 representative letters from domain or display name.
    /// "kaspi.kz" → "KA", "youtube.com" → "YO"
    /// After Task 6 (ServiceLogoRegistry), uncomment the registry lookup below.
    static func extractLetters(from domain: String) -> String {
        // TODO: Uncomment after Task 6 creates ServiceLogoRegistry
        // let displayName = ServiceLogoRegistry.domainMap[domain.lowercased()]?.displayName
        let displayName: String? = nil // placeholder until Task 6

        if let name = displayName {
            let words = name.split(separator: " ")
            if words.count >= 2 {
                let first = String(words[0].prefix(1))
                let second = String(words[1].prefix(1))
                return (first + second).uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        }

        // Fallback: use domain name part (before first dot)
        let namePart = domain.split(separator: ".").first.map(String.init) ?? domain
        return String(namePart.prefix(2)).uppercased()
    }

    /// Deterministic color based on domain using djb2 hash (stable across launches).
    /// Swift's hashValue is randomized per process — NOT suitable for persistent colors.
    static func deterministicColor(for domain: String) -> UIColor {
        let lowered = domain.lowercased()
        var hash: UInt64 = 5381
        for byte in lowered.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }

    /// Render lettermark image
    static func renderLettermark(letters: String, color: UIColor, size: CGFloat) -> UIImage {
        let actualSize = max(size, 64) // minimum render size for quality
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: actualSize, height: actualSize))

        return renderer.image { ctx in
            // Background
            let rect = CGRect(origin: .zero, size: CGSize(width: actualSize, height: actualSize))
            let cornerRadius = actualSize * 0.2
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            color.setFill()
            path.fill()

            // Text
            let fontSize = actualSize * 0.38
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
            ]

            let textSize = (letters as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: (actualSize - textSize.width) / 2,
                y: (actualSize - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (letters as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project and verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

Note: The `ServiceLogoRegistry` reference is commented out with a placeholder. It will be uncommented in Task 6 Step 5 after the registry is created.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/LettermarkProvider.swift
git commit -m "feat: add LettermarkProvider with deterministic colors"
```

---

### Task 5: Refactor LogoDevConfig + Extract LogoDevProvider

**Files:**
- Modify: `Tenra/Services/Core/LogoDevConfig.swift`
- The logo.dev fetch logic will live in `LogoService` refactor (Task 7), but LogoDevProvider is essentially an extraction of the existing fetch from `LogoService`.

`LogoDevProvider` doesn't need its own file — it's small enough to live inside `LogoProvider.swift`. But for clarity per spec, we keep it separate in LogoService's fetch logic. Actually, the cleanest approach: make `LogoDevProvider` a struct inside `LogoProvider.swift`.

- [ ] **Step 1: Add LogoDevProvider to LogoProvider.swift**

Append to `Tenra/Services/Core/LogoProvider.swift`:

```swift
/// Fetches logos from logo.dev API. Returns nil if API key is unavailable.
nonisolated final class LogoDevProvider: LogoProvider {
    let name = "logoDev"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        // Check API key availability internally
        guard let url = LogoDevConfig.logoURL(for: domain) else {
            return nil
        }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }

            return image
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/LogoProvider.swift
git commit -m "feat: add LogoDevProvider with 5s timeout"
```

---

## Chunk 2: ServiceLogoRegistry + Localization

### Task 6: Refactor ServiceLogo to Struct Registry

**Files:**
- Modify: `Tenra/Models/ServiceLogo.swift`
- Modify: `Tenra/Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 1: Add ServiceLogoEntry struct and ServiceLogoRegistry**

Add ABOVE the existing `ServiceLogo` enum (keep it for now) in `ServiceLogo.swift`:

```swift
// MARK: - Service Logo Registry (struct-based)

struct ServiceLogoEntry: Sendable, Identifiable {
    let domain: String
    let displayName: String
    let category: ServiceCategory
    let aliases: [String]

    var id: String { domain }
}

nonisolated enum ServiceLogoRegistry {
    // MARK: - All Services

    static let allServices: [ServiceLogoEntry] = {
        var entries: [ServiceLogoEntry] = []

        // Streaming & Entertainment
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "youtube.com", displayName: "YouTube", category: .streaming, aliases: ["ютуб"]),
            ServiceLogoEntry(domain: "netflix.com", displayName: "Netflix", category: .streaming, aliases: ["нетфликс"]),
            ServiceLogoEntry(domain: "spotify.com", displayName: "Spotify", category: .streaming, aliases: ["спотифай"]),
            ServiceLogoEntry(domain: "music.apple.com", displayName: "Apple Music", category: .streaming, aliases: ["эпл мьюзик"]),
            ServiceLogoEntry(domain: "primevideo.com", displayName: "Amazon Prime", category: .streaming, aliases: ["амазон прайм"]),
            ServiceLogoEntry(domain: "music.amazon.com", displayName: "Amazon Music", category: .streaming, aliases: []),
            ServiceLogoEntry(domain: "disneyplus.com", displayName: "Disney+", category: .streaming, aliases: ["дисней"]),
            ServiceLogoEntry(domain: "tv.apple.com", displayName: "Apple TV+", category: .streaming, aliases: []),
            ServiceLogoEntry(domain: "hulu.com", displayName: "Hulu", category: .streaming, aliases: []),
            ServiceLogoEntry(domain: "max.com", displayName: "HBO Max", category: .streaming, aliases: []),
            ServiceLogoEntry(domain: "paramountplus.com", displayName: "Paramount+", category: .streaming, aliases: []),
            ServiceLogoEntry(domain: "music.youtube.com", displayName: "YouTube Music", category: .streaming, aliases: ["ютуб мьюзик"]),
            ServiceLogoEntry(domain: "pandora.com", displayName: "Pandora", category: .streaming, aliases: []),
            ServiceLogoEntry(domain: "audible.com", displayName: "Audible", category: .streaming, aliases: []),
        ])

        // Productivity & Cloud
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "notion.so", displayName: "Notion", category: .productivity, aliases: ["ноушн"]),
            ServiceLogoEntry(domain: "icloud.com", displayName: "iCloud", category: .productivity, aliases: ["айклауд"]),
            ServiceLogoEntry(domain: "drive.google.com", displayName: "Google Drive", category: .productivity, aliases: ["гугл диск"]),
            ServiceLogoEntry(domain: "one.google.com", displayName: "Google One", category: .productivity, aliases: ["гугл уан"]),
            ServiceLogoEntry(domain: "dropbox.com", displayName: "Dropbox", category: .productivity, aliases: ["дропбокс"]),
            ServiceLogoEntry(domain: "adobe.com", displayName: "Adobe Cloud", category: .productivity, aliases: ["адоб"]),
            ServiceLogoEntry(domain: "microsoft.com", displayName: "Microsoft 365", category: .productivity, aliases: ["майкрософт"]),
            ServiceLogoEntry(domain: "canva.com", displayName: "Canva", category: .productivity, aliases: ["канва"]),
            ServiceLogoEntry(domain: "figma.com", displayName: "Figma", category: .productivity, aliases: ["фигма"]),
            ServiceLogoEntry(domain: "framer.com", displayName: "Framer", category: .productivity, aliases: []),
            ServiceLogoEntry(domain: "grammarly.com", displayName: "Grammarly", category: .productivity, aliases: []),
            ServiceLogoEntry(domain: "slack.com", displayName: "Slack", category: .productivity, aliases: ["слак"]),
            ServiceLogoEntry(domain: "trello.com", displayName: "Trello", category: .productivity, aliases: ["трелло"]),
            ServiceLogoEntry(domain: "zoom.us", displayName: "Zoom", category: .productivity, aliases: ["зум"]),
            ServiceLogoEntry(domain: "cleanshot.com", displayName: "CleanShot", category: .productivity, aliases: []),
            ServiceLogoEntry(domain: "setapp.com", displayName: "Setapp", category: .productivity, aliases: []),
        ])

        // Social & Communication
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "linkedin.com", displayName: "LinkedIn", category: .social, aliases: ["линкедин"]),
            ServiceLogoEntry(domain: "telegram.org", displayName: "Telegram", category: .social, aliases: ["телеграм", "тг"]),
            ServiceLogoEntry(domain: "x.com", displayName: "X (Twitter)", category: .social, aliases: ["твиттер", "twitter"]),
            ServiceLogoEntry(domain: "tinder.com", displayName: "Tinder", category: .social, aliases: ["тиндер"]),
            ServiceLogoEntry(domain: "bumble.com", displayName: "Bumble", category: .social, aliases: ["бамбл"]),
            ServiceLogoEntry(domain: "hinge.co", displayName: "Hinge", category: .social, aliases: []),
        ])

        // Fitness & Health
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "calm.com", displayName: "Calm", category: .fitness, aliases: []),
            ServiceLogoEntry(domain: "headspace.com", displayName: "Headspace", category: .fitness, aliases: []),
            ServiceLogoEntry(domain: "strava.com", displayName: "Strava", category: .fitness, aliases: ["страва"]),
            ServiceLogoEntry(domain: "apple.com/apple-fitness-plus", displayName: "Apple Fitness+", category: .fitness, aliases: []),
            ServiceLogoEntry(domain: "onepeloton.com", displayName: "Peloton", category: .fitness, aliases: []),
            ServiceLogoEntry(domain: "dailyburn.com", displayName: "Daily Burn", category: .fitness, aliases: []),
            ServiceLogoEntry(domain: "waterminder.com", displayName: "Water Minder", category: .fitness, aliases: []),
            ServiceLogoEntry(domain: "whoop.com", displayName: "WHOOP", category: .fitness, aliases: []),
        ])

        // Gaming
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "playstation.com", displayName: "PlayStation Plus", category: .gaming, aliases: ["плейстейшн", "пс плюс"]),
            ServiceLogoEntry(domain: "xbox.com", displayName: "Xbox Game Pass", category: .gaming, aliases: ["иксбокс"]),
            ServiceLogoEntry(domain: "nintendo.com", displayName: "Nintendo Online", category: .gaming, aliases: ["нинтендо"]),
            ServiceLogoEntry(domain: "ea.com", displayName: "EA Play", category: .gaming, aliases: []),
            ServiceLogoEntry(domain: "apple.com/apple-arcade", displayName: "Apple Arcade", category: .gaming, aliases: []),
        ])

        // Developer Tools & AI
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "cursor.sh", displayName: "Cursor", category: .devTools, aliases: ["курсор"]),
            ServiceLogoEntry(domain: "claude.ai", displayName: "Claude", category: .devTools, aliases: ["клод"]),
            ServiceLogoEntry(domain: "chat.openai.com", displayName: "ChatGPT", category: .devTools, aliases: ["чатгпт", "openai"]),
            ServiceLogoEntry(domain: "gemini.google.com", displayName: "Gemini", category: .devTools, aliases: ["джемини"]),
            ServiceLogoEntry(domain: "midjourney.com", displayName: "Midjourney", category: .devTools, aliases: ["миджорни"]),
            ServiceLogoEntry(domain: "github.com", displayName: "GitHub", category: .devTools, aliases: ["гитхаб"]),
            ServiceLogoEntry(domain: "developer.apple.com", displayName: "Apple Developer", category: .devTools, aliases: []),
        ])

        // Services
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "revolut.com", displayName: "Revolut", category: .services, aliases: ["револют"]),
            ServiceLogoEntry(domain: "1password.com", displayName: "1Password", category: .services, aliases: []),
            ServiceLogoEntry(domain: "nordvpn.com", displayName: "NordVPN", category: .services, aliases: []),
            ServiceLogoEntry(domain: "patreon.com", displayName: "Patreon", category: .services, aliases: ["патреон"]),
            ServiceLogoEntry(domain: "nytimes.com", displayName: "The New York Times", category: .services, aliases: []),
            ServiceLogoEntry(domain: "scribd.com", displayName: "Scribd", category: .services, aliases: []),
            ServiceLogoEntry(domain: "skillshare.com", displayName: "Skillshare", category: .services, aliases: []),
            ServiceLogoEntry(domain: "duolingo.com", displayName: "Duolingo", category: .services, aliases: ["дуолинго"]),
            ServiceLogoEntry(domain: "lifecell.ua", displayName: "Lifecell", category: .services, aliases: []),
            ServiceLogoEntry(domain: "vodafone.com", displayName: "Vodafone", category: .services, aliases: []),
            ServiceLogoEntry(domain: "fubo.tv", displayName: "FuboTV", category: .services, aliases: []),
            ServiceLogoEntry(domain: "apple.com/apple-one", displayName: "Apple One", category: .services, aliases: []),
            ServiceLogoEntry(domain: "apple.com/support/products", displayName: "AppleCare+", category: .services, aliases: []),
            ServiceLogoEntry(domain: "wwf.org", displayName: "WWF", category: .services, aliases: []),
            ServiceLogoEntry(domain: "play.google.com", displayName: "Google Play", category: .services, aliases: ["гугл плей"]),
        ])

        // === NEW: KZ/CIS Services ===

        // Local Services (Kazakhstan)
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "kaspi.kz", displayName: "Kaspi.kz", category: .localServices, aliases: ["каспи", "kaspi", "каспий"]),
            ServiceLogoEntry(domain: "kolesa.kz", displayName: "Kolesa.kz", category: .localServices, aliases: ["колеса", "колёса"]),
            ServiceLogoEntry(domain: "krisha.kz", displayName: "Krisha.kz", category: .localServices, aliases: ["крыша"]),
            ServiceLogoEntry(domain: "olx.kz", displayName: "OLX.kz", category: .localServices, aliases: ["олх", "оликс"]),
            ServiceLogoEntry(domain: "2gis.kz", displayName: "2GIS", category: .localServices, aliases: ["2гис", "дубльгис", "дубль гис"]),
            ServiceLogoEntry(domain: "chocofamily.kz", displayName: "Chocofamily", category: .localServices, aliases: ["чокофэмили", "шокофемили"]),
            ServiceLogoEntry(domain: "glovo.com", displayName: "Glovo", category: .localServices, aliases: ["глово"]),
            ServiceLogoEntry(domain: "wolt.com", displayName: "Wolt", category: .localServices, aliases: ["волт"]),
            ServiceLogoEntry(domain: "indrive.com", displayName: "inDrive", category: .localServices, aliases: ["индрайв"]),
            ServiceLogoEntry(domain: "arbuz.kz", displayName: "Arbuz.kz", category: .localServices, aliases: ["арбуз"]),
            ServiceLogoEntry(domain: "chocolife.me", displayName: "Chocolife", category: .localServices, aliases: ["чоколайф"]),
            ServiceLogoEntry(domain: "aviata.kz", displayName: "Aviata", category: .localServices, aliases: ["авиата"]),
            ServiceLogoEntry(domain: "chocotravel.com", displayName: "Chocotravel", category: .localServices, aliases: ["чокотревел"]),
            ServiceLogoEntry(domain: "flip.kz", displayName: "Flip.kz", category: .localServices, aliases: ["флип"]),
            ServiceLogoEntry(domain: "wildberries.kz", displayName: "Wildberries KZ", category: .localServices, aliases: ["вайлдберриз кз"]),
            ServiceLogoEntry(domain: "ozon.kz", displayName: "Ozon KZ", category: .localServices, aliases: ["озон кз"]),
            ServiceLogoEntry(domain: "technodom.kz", displayName: "Technodom", category: .localServices, aliases: ["технодом"]),
            ServiceLogoEntry(domain: "sulpak.kz", displayName: "Sulpak", category: .localServices, aliases: ["сулпак"]),
            ServiceLogoEntry(domain: "mechta.kz", displayName: "Mechta.kz", category: .localServices, aliases: ["мечта"]),
        ])

        // Telecom
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "kcell.kz", displayName: "Kcell", category: .telecom, aliases: ["кселл", "ксел"]),
            ServiceLogoEntry(domain: "beeline.kz", displayName: "Beeline KZ", category: .telecom, aliases: ["билайн"]),
            ServiceLogoEntry(domain: "tele2.kz", displayName: "Tele2 KZ", category: .telecom, aliases: ["теле2"]),
            ServiceLogoEntry(domain: "altel.kz", displayName: "Altel", category: .telecom, aliases: ["алтел"]),
            ServiceLogoEntry(domain: "activ.kz", displayName: "Activ", category: .telecom, aliases: ["актив"]),
            ServiceLogoEntry(domain: "telecom.kz", displayName: "Kazakhtelecom", category: .telecom, aliases: ["казахтелеком", "мегалайн", "megaline"]),
            ServiceLogoEntry(domain: "id.kz", displayName: "iD Mobile", category: .telecom, aliases: []),
        ])

        // CIS Services
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "music.yandex.ru", displayName: "Yandex Music", category: .cis, aliases: ["яндекс музыка", "yandex music"]),
            ServiceLogoEntry(domain: "kinopoisk.ru", displayName: "Kinopoisk", category: .cis, aliases: ["кинопоиск"]),
            ServiceLogoEntry(domain: "vk.com", displayName: "VK", category: .cis, aliases: ["вк", "вконтакте", "vkontakte"]),
            ServiceLogoEntry(domain: "ozon.ru", displayName: "Ozon", category: .cis, aliases: ["озон"]),
            ServiceLogoEntry(domain: "wildberries.ru", displayName: "Wildberries", category: .cis, aliases: ["вайлдберриз", "вб"]),
            ServiceLogoEntry(domain: "sbermarket.ru", displayName: "SberMarket", category: .cis, aliases: ["сбермаркет"]),
            ServiceLogoEntry(domain: "tinkoff.ru", displayName: "Tinkoff", category: .cis, aliases: ["тинькофф", "тинькоф", "тбанк", "t-bank"]),
            ServiceLogoEntry(domain: "mts.ru", displayName: "MTS", category: .cis, aliases: ["мтс"]),
            ServiceLogoEntry(domain: "megafon.ru", displayName: "Megafon", category: .cis, aliases: ["мегафон"]),
            ServiceLogoEntry(domain: "yandex.ru", displayName: "Yandex Plus", category: .cis, aliases: ["яндекс плюс", "yandex plus"]),
            ServiceLogoEntry(domain: "ivi.ru", displayName: "ivi", category: .cis, aliases: ["иви"]),
            ServiceLogoEntry(domain: "okko.tv", displayName: "Okko", category: .cis, aliases: ["окко"]),
            ServiceLogoEntry(domain: "more.tv", displayName: "more.tv", category: .cis, aliases: []),
            ServiceLogoEntry(domain: "sber.ru", displayName: "Sber", category: .cis, aliases: ["сбер", "сбербанк"]),
            ServiceLogoEntry(domain: "yandex.go", displayName: "Yandex Go", category: .cis, aliases: ["яндекс го", "яндекс такси"]),
            ServiceLogoEntry(domain: "yandex.food", displayName: "Yandex Eats", category: .cis, aliases: ["яндекс еда"]),
            ServiceLogoEntry(domain: "market.yandex.ru", displayName: "Yandex Market", category: .cis, aliases: ["яндекс маркет"]),
        ])

        return entries
    }()

    // MARK: - Lookup Dictionaries

    /// Domain → entry (exact match)
    static let domainMap: [String: ServiceLogoEntry] = {
        var map: [String: ServiceLogoEntry] = [:]
        for entry in allServices {
            map[entry.domain.lowercased()] = entry
        }
        return map
    }()

    /// displayName + aliases + domain → entry
    static let aliasMap: [String: ServiceLogoEntry] = {
        var map: [String: ServiceLogoEntry] = [:]
        for entry in allServices {
            map[entry.domain.lowercased()] = entry
            map[entry.displayName.lowercased()] = entry
            for alias in entry.aliases {
                map[alias.lowercased()] = entry
            }
        }
        return map
    }()

    // MARK: - Query Methods

    static func services(for category: ServiceCategory) -> [ServiceLogoEntry] {
        allServices.filter { $0.category == category }
    }

    /// Fuzzy search by displayName and aliases
    static func search(query: String) -> [ServiceLogoEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        // Exact alias match first
        if let exact = aliasMap[q] {
            return [exact]
        }

        // Contains match
        return allServices.filter { entry in
            entry.displayName.localizedCaseInsensitiveContains(q) ||
            entry.aliases.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// Resolve any input (domain, displayName, alias) to a domain string
    static func resolveDomain(from input: String) -> String {
        let lowered = input.lowercased()
        if let entry = domainMap[lowered] { return entry.domain }
        if let entry = aliasMap[lowered] { return entry.domain }
        return input
    }
}
```

- [ ] **Step 2: Add 3 new ServiceCategory cases**

In the same file, update `ServiceCategory`:

```swift
enum ServiceCategory: String, CaseIterable {
    case streaming
    case productivity
    case social
    case fitness
    case gaming
    case devTools
    case services
    case localServices
    case telecom
    case cis

    var localizedTitle: String {
        switch self {
        case .streaming:
            return String(localized: "iconPicker.streaming")
        case .productivity:
            return String(localized: "iconPicker.productivity")
        case .social:
            return String(localized: "iconPicker.social")
        case .fitness:
            return String(localized: "iconPicker.fitness")
        case .gaming:
            return String(localized: "iconPicker.gaming")
        case .devTools:
            return String(localized: "iconPicker.devTools")
        case .services:
            return String(localized: "iconPicker.services")
        case .localServices:
            return String(localized: "iconPicker.localServices")
        case .telecom:
            return String(localized: "iconPicker.telecom")
        case .cis:
            return String(localized: "iconPicker.cis")
        }
    }

    /// Legacy: returns old enum cases. Use ServiceLogoRegistry.services(for:) instead.
    func services() -> [ServiceLogo] {
        ServiceLogo.allCases.filter { $0.category == self }
    }

    /// Registry-backed: returns all entries including new KZ/CIS categories.
    func registryServices() -> [ServiceLogoEntry] {
        ServiceLogoRegistry.services(for: self)
    }
}
```

- [ ] **Step 3: Add localization strings**

Append to `en.lproj/Localizable.strings`:
```
"iconPicker.localServices" = "Local Services";
"iconPicker.telecom" = "Telecom";
"iconPicker.cis" = "CIS Services";
"iconPicker.suggestions" = "Suggestions";
"iconPicker.onlineSearch" = "Online";
"iconPicker.brandDomainHint" = "Enter brand domain (e.g. netflix.com)";
```

Append to `ru.lproj/Localizable.strings`:
```
"iconPicker.localServices" = "Местные сервисы";
"iconPicker.telecom" = "Телеком";
"iconPicker.cis" = "СНГ сервисы";
"iconPicker.suggestions" = "Предложения";
"iconPicker.onlineSearch" = "Онлайн";
"iconPicker.brandDomainHint" = "Введите домен бренда (например: netflix.com)";
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 5: Uncomment LettermarkProvider's ServiceLogoRegistry reference**

Now that `ServiceLogoRegistry` exists, uncomment the `ServiceLogoRegistry.domainMap` lookup in `LettermarkProvider.extractLetters(from:)`.

- [ ] **Step 6: Verify build again**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 7: Commit**

```bash
git add Tenra/Models/ServiceLogo.swift \
  Tenra/Tenra/en.lproj/Localizable.strings \
  Tenra/Tenra/ru.lproj/Localizable.strings \
  Tenra/Services/Core/LettermarkProvider.swift
git commit -m "feat: add ServiceLogoRegistry with 150+ services and KZ/CIS entries"
```

---

## Chunk 3: LogoService Refactor + BrandLogoView Simplification

### Task 7: Refactor LogoService to Use Provider Chain

**Files:**
- Modify: `Tenra/Services/Core/LogoService.swift`

- [ ] **Step 1: Rewrite LogoService**

Replace the entire content of `LogoService.swift`:

```swift
//
//  LogoService.swift
//  Tenra
//
//  Central logo service using waterfall provider chain
//

import Foundation
import UIKit

/// Central logo service with waterfall provider chain.
/// Chain: Local → LogoDev → GoogleFavicon → Lettermark
final class LogoService {
    static let shared = LogoService()

    // Memory cache
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache = LogoDiskCache.shared

    // Provider chain (order = priority)
    // LogoService is NOT @Observable — no @ObservationIgnored needed
    private let providers: [any LogoProvider] = [
        LocalLogoProvider(),
        LogoDevProvider(),
        GoogleFaviconProvider(),
        LettermarkProvider(),
    ]

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }

    /// Loads a brand logo through the provider chain.
    /// Resolves brandName to domain before cache/fetch.
    /// Never throws — LettermarkProvider always succeeds.
    @MainActor
    func logoImage(brandName: String) async -> UIImage? {
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }

        // Resolve to domain for consistent cache key
        let domain = ServiceLogoRegistry.resolveDomain(from: normalizedName)
        let cacheKey = domain as NSString

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = diskCache.load(for: domain) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }

        // 3. Provider chain
        if let image = await LogoProviderChain.fetch(
            domain: domain,
            size: 128,
            providers: providers
        ) {
            memoryCache.setObject(image, forKey: cacheKey)
            diskCache.save(image, for: domain)
            return image
        }

        return nil
    }

    /// Prefetch logos for a list of brand names.
    nonisolated func prefetch(brandNames: [String]) {
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for brandName in brandNames {
                    group.addTask { @MainActor in
                        _ = await LogoService.shared.logoImage(brandName: brandName)
                    }
                }
            }
        }
    }

    /// Check if a logo is cached (memory or disk).
    @MainActor
    func isCached(brandName: String) -> Bool {
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = ServiceLogoRegistry.resolveDomain(from: normalizedName)

        if memoryCache.object(forKey: domain as NSString) != nil {
            return true
        }

        return diskCache.exists(for: domain)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

Note: There may be errors in `BrandLogoView` because it still uses `try? await` and `LogoDevConfig.isAvailable`. These will be fixed in the next task.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/LogoService.swift
git commit -m "refactor: LogoService uses waterfall provider chain, drops throws"
```

---

### Task 8: Simplify BrandLogoView

**Files:**
- Modify: `Tenra/Views/Components/Icons/BrandLogoView.swift`

- [ ] **Step 1: Rewrite BrandLogoView to chain-only**

Replace the entire content:

```swift
//
//  BrandLogoView.swift
//  Tenra
//
//  SwiftUI component for displaying brand logos via provider chain
//

import SwiftUI

/// Displays a brand logo loaded through the LogoService provider chain.
/// No longer uses AsyncImage — relies entirely on the chain result.
/// Uses .task(id:) for automatic cancellation on brandName change.
struct BrandLogoView: View {
    let brandName: String?
    let size: CGFloat

    @State private var logoImage: UIImage?
    @State private var isLoading = false

    init(brandName: String?, size: CGFloat = 32) {
        self.brandName = brandName
        self.size = size
    }

    var body: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                fallbackIcon
            }
        }
        .task(id: brandName) {
            guard let brandName,
                  !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logoImage = nil
                isLoading = false
                return
            }

            isLoading = true
            let image = await LogoService.shared.logoImage(brandName: brandName)
            logoImage = image
            isLoading = false
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "creditcard")
            .font(.system(size: size * 0.6))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

#Preview {
    VStack(spacing: 20) {
        BrandLogoView(brandName: "netflix.com", size: 40)
        BrandLogoView(brandName: "spotify.com", size: 32)
        BrandLogoView(brandName: nil, size: 32)
    }
    .padding()
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 3: Check for any remaining `try? await LogoService` references**

Run: `grep -rn "try.*logoImage" Tenra/` — should return 0 results.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Views/Components/Icons/BrandLogoView.swift
git commit -m "refactor: BrandLogoView drops AsyncImage, uses chain-only loading"
```

---

## Chunk 4: IconPickerView Two-Phase Search

### Task 9: Update IconPickerView with Two-Phase Search

**Files:**
- Modify: `Tenra/Views/Components/Icons/IconPickerView.swift`

- [ ] **Step 1: Update LogoItem enum to support ServiceLogoEntry**

Replace the `LogoItem` enum and `LogosTabView`:

In `IconPickerView.swift`, replace `LogoItem` enum (lines 241-262) with:

```swift
private enum LogoItem: Identifiable {
    case bank(BankLogo)
    case service(ServiceLogoEntry)

    var id: String {
        switch self {
        case .bank(let logo):
            return "bank_\(logo.rawValue)"
        case .service(let entry):
            return "service_\(entry.domain)"
        }
    }

    var iconSource: IconSource {
        switch self {
        case .bank(let logo):
            return .bankLogo(logo)
        case .service(let entry):
            return .brandService(entry.domain)
        }
    }
}
```

- [ ] **Step 2: Replace LogosTabView with two-phase search**

Replace the entire `LogosTabView` (lines 145-203) with:

```swift
private struct LogosTabView: View {
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private let banks: [BankLogo] = [
        .alatauCityBank, .halykBank, .kaspi, .homeCredit,
        .eurasian, .forte, .jusan, .otbasy, .centerCredit,
        .bereke, .alfaBank, .freedom, .sber, .vtb,
        .tbank, .rbk, .nurBank, .asiaCredit,
        .tengri, .brk, .citi, .ebr, .bankOfChina,
        .moscowBank, .icbc, .shinhan, .kbo, .atf
    ]

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [ServiceLogoEntry] {
        ServiceLogoRegistry.search(query: searchText)
    }

    var body: some View {
        Group {
            if isSearching {
                SearchResultsView(
                    searchText: searchText,
                    results: Array(searchResults.prefix(8)),
                    selectedSource: $selectedSource
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                        // Banks
                        LogoCategorySection(
                            title: String(localized: "iconPicker.banks"),
                            items: banks.map { .bank($0) },
                            selectedSource: $selectedSource
                        )

                        // Service categories from registry
                        ForEach(ServiceCategory.allCases, id: \.rawValue) { category in
                            let entries = ServiceLogoRegistry.services(for: category)
                            if !entries.isEmpty {
                                LogoCategorySection(
                                    title: category.localizedTitle,
                                    items: entries.map { .service($0) },
                                    selectedSource: $selectedSource
                                )
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.lg)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: String(localized: "iconPicker.searchOnline")
        )
    }
}
```

- [ ] **Step 3: Replace OnlineSearchResultsView with SearchResultsView**

Replace the `OnlineSearchResultsView` struct (lines 291-323) with:

```swift
/// Two-phase search: local suggestions + online domain fallback
private struct SearchResultsView: View {
    let searchText: String
    let results: [ServiceLogoEntry]
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether input looks like a domain (contains a dot)
    private var looksLikeDomain: Bool {
        trimmedSearch.contains(".")
    }

    var body: some View {
        List {
            // Phase 1: Local suggestions
            if !results.isEmpty {
                Section {
                    ForEach(results) { entry in
                        OnlineLogoRow(
                            brandName: entry.domain,
                            displayLabel: entry.displayName,
                            isSelected: selectedSource == .brandService(entry.domain),
                            onSelect: {
                                HapticManager.selection()
                                selectedSource = .brandService(entry.domain)
                                dismiss()
                            }
                        )
                    }
                } header: {
                    Text(String(localized: "iconPicker.suggestions"))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            // Phase 2: Online domain search
            Section {
                if looksLikeDomain {
                    OnlineLogoRow(
                        brandName: trimmedSearch,
                        displayLabel: trimmedSearch,
                        isSelected: selectedSource == .brandService(trimmedSearch),
                        onSelect: {
                            HapticManager.selection()
                            selectedSource = .brandService(trimmedSearch)
                            dismiss()
                        }
                    )
                } else {
                    // Try .com and .kz variants
                    OnlineLogoRow(
                        brandName: "\(trimmedSearch).com",
                        displayLabel: "\(trimmedSearch).com",
                        isSelected: selectedSource == .brandService("\(trimmedSearch).com"),
                        onSelect: {
                            HapticManager.selection()
                            selectedSource = .brandService("\(trimmedSearch).com")
                            dismiss()
                        }
                    )
                    OnlineLogoRow(
                        brandName: "\(trimmedSearch).kz",
                        displayLabel: "\(trimmedSearch).kz",
                        isSelected: selectedSource == .brandService("\(trimmedSearch).kz"),
                        onSelect: {
                            HapticManager.selection()
                            selectedSource = .brandService("\(trimmedSearch).kz")
                            dismiss()
                        }
                    )
                }
            } header: {
                Text(String(localized: "iconPicker.onlineSearch"))
                    .foregroundStyle(AppColors.textPrimary)
            } footer: {
                Text(String(localized: "iconPicker.brandDomainHint", defaultValue: "Enter brand domain (e.g. netflix.com)"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
```

- [ ] **Step 4: Update OnlineLogoRow to accept displayLabel**

Replace the `OnlineLogoRow` struct (lines 327-356):

```swift
private struct OnlineLogoRow: View {
    let brandName: String
    let displayLabel: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.md) {
                IconView(
                    source: .brandService(brandName),
                    size: AppIconSize.xxl
                )

                Text(displayLabel)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 6: Commit**

```bash
git add Tenra/Views/Components/Icons/IconPickerView.swift
git commit -m "feat: IconPickerView two-phase search with local suggestions + online fallback"
```

---

### Task 10: Final Build Verification & Cleanup

**Files:**
- Possibly modify: any file with remaining `try? await LogoService` or `LogoDevConfig.isAvailable` guard references

- [ ] **Step 1: Search for stale references**

Run these searches:
```bash
grep -rn "try.*logoImage" Tenra/ --include="*.swift"
grep -rn "LogoDevConfig.isAvailable" Tenra/ --include="*.swift" | grep -v "LogoDevConfig.swift" | grep -v "LogoProvider.swift"
grep -rn "ServiceLogo\." Tenra/ --include="*.swift" | grep -v "ServiceLogo.swift" | grep -v "ServiceLogoEntry" | grep -v "ServiceLogoRegistry"
```

Fix any stale references found. The old `ServiceLogo` enum should still work since we kept it, but `IconPickerView` should now use `ServiceLogoRegistry`.

- [ ] **Step 2: Full clean build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

- [ ] **Step 3: Verify no warnings from new code**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "warning:" | grep -E "(LogoProvider|LocalLogo|GoogleFavicon|Lettermark|ServiceLogoRegistry|BrandLogoView)" | head -20`

Fix any warnings.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: cleanup stale references after logo provider chain migration"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | LogoProvider protocol + chain runner | Services/Core/LogoProvider.swift |
| 2 | LocalLogoProvider (BankLogo assets) | Services/Core/LocalLogoProvider.swift |
| 3 | GoogleFaviconProvider | Services/Core/GoogleFaviconProvider.swift |
| 4 | LettermarkProvider | Services/Core/LettermarkProvider.swift |
| 5 | LogoDevProvider (extracted) | Services/Core/LogoProvider.swift |
| 6 | ServiceLogoRegistry + new categories + localization | Models/ServiceLogo.swift + .strings |
| 7 | LogoService refactor (chain, no throws, domain resolve) | Services/Core/LogoService.swift |
| 8 | BrandLogoView simplification | Views/Components/Icons/BrandLogoView.swift |
| 9 | IconPickerView two-phase search | Views/Components/Icons/IconPickerView.swift |
| 10 | Final build verification + cleanup | Various |
