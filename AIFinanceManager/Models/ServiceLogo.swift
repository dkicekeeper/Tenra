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
    /// Custom filename in Supabase Storage (without extension). If nil, domain is used.
    let logoFilename: String?

    nonisolated var id: String { domain }

    init(domain: String, displayName: String, category: ServiceCategory, aliases: [String], logoFilename: String? = nil) {
        self.domain = domain
        self.displayName = displayName
        self.category = category
        self.aliases = aliases
        self.logoFilename = logoFilename
    }
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

        // === Banks ===
        // logoFilename matches the actual filename in Supabase Storage (without .png extension)
        entries.append(contentsOf: [
            ServiceLogoEntry(domain: "alataucitybank.kz", displayName: "Alatau City Bank", category: .banks, aliases: ["алатау"], logoFilename: "Alataucitybank"),
            ServiceLogoEntry(domain: "halykbank.kz", displayName: "Halyk Bank", category: .banks, aliases: ["халык", "halyk"], logoFilename: "Halyk_bank"),
            ServiceLogoEntry(domain: "kaspi.kz", displayName: "Kaspi", category: .banks, aliases: ["каспи", "kaspi"], logoFilename: "Kaspi"),
            ServiceLogoEntry(domain: "homecredit.kz", displayName: "Home Credit Bank", category: .banks, aliases: ["хоум кредит"], logoFilename: "Home_Credit"),
            ServiceLogoEntry(domain: "eubank.kz", displayName: "Eurasian Bank", category: .banks, aliases: ["евразийский"], logoFilename: "Eurasian"),
            ServiceLogoEntry(domain: "forte.kz", displayName: "Forte Bank", category: .banks, aliases: ["форте"], logoFilename: "Forte"),
            ServiceLogoEntry(domain: "jusan.kz", displayName: "Jusan Bank", category: .banks, aliases: ["жусан"], logoFilename: "Jusan"),
            ServiceLogoEntry(domain: "hcsbk.kz", displayName: "Otbasy Bank", category: .banks, aliases: ["отбасы"], logoFilename: "Otbasy"),
            ServiceLogoEntry(domain: "bcc.kz", displayName: "Bank Center Credit", category: .banks, aliases: ["центркредит", "цк"], logoFilename: "Center_Credit"),
            ServiceLogoEntry(domain: "berekebank.kz", displayName: "Bereke Bank", category: .banks, aliases: ["береке"], logoFilename: "Bereke"),
            ServiceLogoEntry(domain: "alfabank.kz", displayName: "Alfa Bank", category: .banks, aliases: ["альфа банк", "альфа"], logoFilename: "Alfa_bank"),
            ServiceLogoEntry(domain: "ffin.kz", displayName: "Freedom Bank", category: .banks, aliases: ["фридом"], logoFilename: "Freedom"),
            ServiceLogoEntry(domain: "sberbank.kz", displayName: "Sber", category: .banks, aliases: ["сбер", "сбербанк"], logoFilename: "Sber"),
            ServiceLogoEntry(domain: "vtb.kz", displayName: "VTB", category: .banks, aliases: ["втб"], logoFilename: "VTB"),
            ServiceLogoEntry(domain: "tbank.kz", displayName: "T Bank", category: .banks, aliases: ["т банк", "тинькофф банк"], logoFilename: "Tbank"),
            ServiceLogoEntry(domain: "rbk.kz", displayName: "Bank RBK", category: .banks, aliases: ["рбк"], logoFilename: "Rbk"),
            ServiceLogoEntry(domain: "nurbank.kz", displayName: "Nur Bank", category: .banks, aliases: ["нур банк"], logoFilename: "Nur_Bank"),
            ServiceLogoEntry(domain: "asiacreditbank.kz", displayName: "Asia Credit Bank", category: .banks, aliases: ["азия кредит"], logoFilename: "AsiaCredit"),
            ServiceLogoEntry(domain: "tengribank.kz", displayName: "Tengri Bank", category: .banks, aliases: ["тенгри"], logoFilename: "Tengri"),
            ServiceLogoEntry(domain: "kdb.kz", displayName: "BRK Bank", category: .banks, aliases: ["брк"], logoFilename: "BRK"),
            ServiceLogoEntry(domain: "altynbank.kz", displayName: "Altyn Bank", category: .banks, aliases: ["алтын", "altyn"], logoFilename: "Altyn"),
            ServiceLogoEntry(domain: "kazpost.kz", displayName: "Qazpost Bank", category: .banks, aliases: ["казпочта", "казпост", "qazpost"], logoFilename: "Kaz_post"),
            ServiceLogoEntry(domain: "citibank.kz", displayName: "Citibank", category: .banks, aliases: ["сити"], logoFilename: "Citi"),
            ServiceLogoEntry(domain: "bank-china.kz", displayName: "Bank of China", category: .banks, aliases: [], logoFilename: "Bank_of_China"),
            ServiceLogoEntry(domain: "icbc.kz", displayName: "ICBC", category: .banks, aliases: [], logoFilename: "ICBC"),
            ServiceLogoEntry(domain: "shinhan.kz", displayName: "Shinhan", category: .banks, aliases: [], logoFilename: "Shinhan"),
            ServiceLogoEntry(domain: "atfbank.kz", displayName: "ATF Bank", category: .banks, aliases: ["атф"], logoFilename: "ATF"),
        ])

        // === NEW: KZ/CIS Services ===

        // Local Services (Kazakhstan)
        entries.append(contentsOf: [
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

    /// Resolve the Supabase Storage filename for a domain.
    /// Returns logoFilename if set, otherwise the domain itself.
    static func resolveLogoFilename(for domain: String) -> String {
        if let entry = domainMap[domain.lowercased()], let filename = entry.logoFilename {
            return filename
        }
        return domain
    }
}


enum ServiceCategory: String, CaseIterable {
    case banks
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
        case .banks:
            return String(localized: "iconPicker.banks")
        case .localServices:
            return String(localized: "iconPicker.localServices")
        case .telecom:
            return String(localized: "iconPicker.telecom")
        case .cis:
            return String(localized: "iconPicker.cis")
        }
    }

    /// Returns all entries for this category.
    func services() -> [ServiceLogoEntry] {
        ServiceLogoRegistry.services(for: self)
    }
}
