//
//  ServiceLogo.swift
//  AIFinanceManager
//
//  Popular service brands organized by category
//

import Foundation

// MARK: - Service Logo Registry (struct-based)

struct ServiceLogoEntry: Sendable, Identifiable {
    let domain: String
    let displayName: String
    let category: ServiceCategory
    let aliases: [String]

    nonisolated var id: String { domain }
}

nonisolated enum ServiceLogoRegistry {
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

    static let domainMap: [String: ServiceLogoEntry] = {
        var map: [String: ServiceLogoEntry] = [:]
        for entry in allServices {
            map[entry.domain.lowercased()] = entry
        }
        return map
    }()

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

    static func services(for category: ServiceCategory) -> [ServiceLogoEntry] {
        allServices.filter { $0.category == category }
    }

    static func search(query: String) -> [ServiceLogoEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        if let exact = aliasMap[q] {
            return [exact]
        }
        return allServices.filter { entry in
            entry.displayName.localizedCaseInsensitiveContains(q) ||
            entry.aliases.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    static func resolveDomain(from input: String) -> String {
        let lowered = input.lowercased()
        if let entry = domainMap[lowered] { return entry.domain }
        if let entry = aliasMap[lowered] { return entry.domain }
        return input
    }
}

enum ServiceLogo: String, CaseIterable, Identifiable {
    // MARK: - Streaming & Entertainment
    case youtube = "youtube.com"
    case netflix = "netflix.com"
    case spotify = "spotify.com"
    case appleMusic = "music.apple.com"
    case amazonPrime = "primevideo.com"
    case amazonMusic = "music.amazon.com"
    case disneyPlus = "disneyplus.com"
    case appleTVPlus = "tv.apple.com"
    case hulu = "hulu.com"
    case hboMax = "max.com"
    case paramountPlus = "paramountplus.com"
    case youtubeMusic = "music.youtube.com"
    case pandora = "pandora.com"
    case audible = "audible.com"

    // MARK: - Productivity & Cloud
    case notion = "notion.so"
    case icloud = "icloud.com"
    case googleDrive = "drive.google.com"
    case googleOne = "one.google.com"
    case dropbox = "dropbox.com"
    case adobeCloud = "adobe.com"
    case microsoft365 = "microsoft.com"
    case canva = "canva.com"
    case figma = "figma.com"
    case framer = "framer.com"
    case grammarly = "grammarly.com"
    case slack = "slack.com"
    case trello = "trello.com"
    case zoom = "zoom.us"
    case cleanshot = "cleanshot.com"
    case setapp = "setapp.com"

    // MARK: - Social & Communication
    case linkedin = "linkedin.com"
    case telegram = "telegram.org"
    case twitter = "x.com"
    case tinder = "tinder.com"
    case bumble = "bumble.com"
    case hinge = "hinge.co"

    // MARK: - Fitness & Health
    case calm = "calm.com"
    case headspace = "headspace.com"
    case strava = "strava.com"
    case appleFitnessPlus = "apple.com/apple-fitness-plus"
    case peloton = "onepeloton.com"
    case dailyBurn = "dailyburn.com"
    case waterMinder = "waterminder.com"
    case whoop = "whoop.com"

    // MARK: - Gaming
    case playstationPlus = "playstation.com"
    case xboxGamePass = "xbox.com"
    case nintendoOnline = "nintendo.com"
    case eaPlay = "ea.com"
    case appleArcade = "apple.com/apple-arcade"

    // MARK: - Developer Tools & AI
    case cursor = "cursor.sh"
    case claude = "claude.ai"
    case chatGPT = "chat.openai.com"
    case gemini = "gemini.google.com"
    case midjourney = "midjourney.com"
    case github = "github.com"
    case appleDeveloper = "developer.apple.com"

    // MARK: - Services
    case revolut = "revolut.com"
    case onePassword = "1password.com"
    case nordVPN = "nordvpn.com"
    case patreon = "patreon.com"
    case nytimes = "nytimes.com"
    case scribd = "scribd.com"
    case skillshare = "skillshare.com"
    case duolingo = "duolingo.com"
    case lifecell = "lifecell.ua"
    case vodafone = "vodafone.com"
    case fuboTV = "fubo.tv"
    case appleOne = "apple.com/apple-one"
    case appleCarePlus = "apple.com/support/products"
    case wwf = "wwf.org"
    case googlePlay = "play.google.com"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .netflix: return "Netflix"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .amazonPrime: return "Amazon Prime"
        case .amazonMusic: return "Amazon Music"
        case .disneyPlus: return "Disney+"
        case .appleTVPlus: return "Apple TV+"
        case .hulu: return "Hulu"
        case .hboMax: return "HBO Max"
        case .paramountPlus: return "Paramount+"
        case .youtubeMusic: return "YouTube Music"
        case .pandora: return "Pandora"
        case .audible: return "Audible"
        case .notion: return "Notion"
        case .icloud: return "iCloud"
        case .googleDrive: return "Google Drive"
        case .googleOne: return "Google One"
        case .dropbox: return "Dropbox"
        case .adobeCloud: return "Adobe Cloud"
        case .microsoft365: return "Microsoft 365"
        case .canva: return "Canva"
        case .figma: return "Figma"
        case .framer: return "Framer"
        case .grammarly: return "Grammarly"
        case .slack: return "Slack"
        case .trello: return "Trello"
        case .zoom: return "Zoom"
        case .cleanshot: return "CleanShot"
        case .setapp: return "Setapp"
        case .linkedin: return "LinkedIn"
        case .telegram: return "Telegram"
        case .twitter: return "X (Twitter)"
        case .tinder: return "Tinder"
        case .bumble: return "Bumble"
        case .hinge: return "Hinge"
        case .calm: return "Calm"
        case .headspace: return "Headspace"
        case .strava: return "Strava"
        case .appleFitnessPlus: return "Apple Fitness+"
        case .peloton: return "Peloton"
        case .dailyBurn: return "Daily Burn"
        case .waterMinder: return "Water Minder"
        case .whoop: return "WHOOP"
        case .playstationPlus: return "PlayStation Plus"
        case .xboxGamePass: return "Xbox Game Pass"
        case .nintendoOnline: return "Nintendo Online"
        case .eaPlay: return "EA Play"
        case .appleArcade: return "Apple Arcade"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .chatGPT: return "ChatGPT"
        case .gemini: return "Gemini"
        case .midjourney: return "Midjourney"
        case .github: return "GitHub"
        case .appleDeveloper: return "Apple Developer"
        case .revolut: return "Revolut"
        case .onePassword: return "1Password"
        case .nordVPN: return "NordVPN"
        case .patreon: return "Patreon"
        case .nytimes: return "The New York Times"
        case .scribd: return "Scribd"
        case .skillshare: return "Skillshare"
        case .duolingo: return "Duolingo"
        case .lifecell: return "Lifecell"
        case .vodafone: return "Vodafone"
        case .fuboTV: return "FuboTV"
        case .appleOne: return "Apple One"
        case .appleCarePlus: return "AppleCare+"
        case .wwf: return "WWF"
        case .googlePlay: return "Google Play"
        }
    }

    var category: ServiceCategory {
        switch self {
        case .youtube, .netflix, .spotify, .appleMusic, .amazonPrime,
             .amazonMusic, .disneyPlus, .appleTVPlus, .hulu, .hboMax,
             .paramountPlus, .youtubeMusic, .pandora, .audible:
            return .streaming

        case .notion, .icloud, .googleDrive, .googleOne, .dropbox,
             .adobeCloud, .microsoft365, .canva, .figma, .framer,
             .grammarly, .slack, .trello, .zoom, .cleanshot, .setapp:
            return .productivity

        case .linkedin, .telegram, .twitter, .tinder, .bumble, .hinge:
            return .social

        case .calm, .headspace, .strava, .appleFitnessPlus, .peloton,
             .dailyBurn, .waterMinder, .whoop:
            return .fitness

        case .playstationPlus, .xboxGamePass, .nintendoOnline, .eaPlay, .appleArcade:
            return .gaming

        case .cursor, .claude, .chatGPT, .gemini, .midjourney, .github, .appleDeveloper:
            return .devTools

        case .revolut, .onePassword, .nordVPN, .patreon, .nytimes,
             .scribd, .skillshare, .duolingo, .lifecell, .vodafone,
             .fuboTV, .appleOne, .appleCarePlus, .wwf, .googlePlay:
            return .services
        }
    }
}

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
