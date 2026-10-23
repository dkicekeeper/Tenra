//
//  VoiceInputParser.swift
//  Tenra
//
//  Created on 2024
//

import Foundation

// MARK: - Recognized Entity

/// Represents a recognized entity in the transcribed text
struct RecognizedEntity {
    /// Type of entity
    enum EntityType {
        case amount
        case currency
        case category
        case subcategory
        case account
        case date
        case transactionType // income/expense keywords
    }

    /// Type of the recognized entity
    let type: EntityType

    /// Range of the entity in the original text
    let range: NSRange

    /// Extracted value
    let value: String

    /// Confidence level (0.0 - 1.0)
    let confidence: Double
}

class VoiceInputParser {
    // MARK: - Dynamic Data Sources (Weak References)

    /// Reference to CategoriesViewModel for live category data
    private weak var categoriesViewModel: CategoriesViewModel?

    /// Reference to AccountsViewModel for live account data
    private weak var accountsViewModel: AccountsViewModel?

    /// Reference to TransactionsViewModel for usage statistics
    private weak var transactionsViewModel: TransactionsViewModel?

    // MARK: - Computed Properties for Live Data

    /// Live categories from ViewModel
    private var liveCategories: [CustomCategory] {
        categoriesViewModel?.customCategories ?? []
    }

    /// Live subcategories from ViewModel
    private var liveSubcategories: [Subcategory] {
        categoriesViewModel?.subcategories ?? []
    }

    /// Live accounts from ViewModel
    private var liveAccounts: [Account] {
        accountsViewModel?.accounts ?? []
    }

    /// Cached smart default account — computed once per parse() call
    private var cachedDefaultAccount: Account?

    /// Per-parse cache of category → smart default. parseMulti() may resolve
    /// several different categories in one utterance; each lookup hits the
    /// tracker once and we reuse the result for subsequent clauses.
    private var cachedDefaultsByCategory: [String: Account] = [:]

    /// External hook for tests. Production code uses `VoiceLearningStore.shared`.
    var learningStore: VoiceLearningStore = .shared

    /// Live transactions for usage analysis
    private var liveTransactions: [Transaction] {
        transactionsViewModel?.allTransactions ?? []
    }

    /// Category keyword mapping for entity detection — cached to avoid re-allocation per call
    private lazy var categoryMap: [String: (category: String, subcategory: String?)] = [
            // Транспорт - сначала подкатегории
            "такси": ("Транспорт", "Такси"),
            "uber": ("Транспорт", "Такси"),
            "yandex": ("Транспорт", "Такси"),
            "яндекс": ("Транспорт", "Такси"),
            "бензин": ("Транспорт", "Бензин"),
            "заправка": ("Транспорт", "Бензин"),
            "парковка": ("Транспорт", "Парковка"),
            "автобус": ("Транспорт", nil),
            "метро": ("Транспорт", nil),
            "проезд": ("Транспорт", nil),
            "транспорт": ("Транспорт", nil),

            // Еда - синонимы
            "кафе": ("Кафе и рестораны", nil),
            "кофе": ("Кафе и рестораны", "Кофе"),
            "ресторан": ("Кафе и рестораны", nil),
            "обед": ("Кафе и рестораны", nil),
            "ужин": ("Кафе и рестораны", nil),
            "завтрак": ("Кафе и рестораны", nil),
            "еда": ("Кафе и рестораны", nil),
            "столовая": ("Кафе и рестораны", nil),
            "доставка": ("Кафе и рестораны", "Доставка"),
            "доставку": ("Кафе и рестораны", "Доставка"),
            "доставки": ("Кафе и рестораны", "Доставка"),
            "доставке": ("Кафе и рестораны", "Доставка"),
            "курьер": ("Кафе и рестораны", "Доставка"),
            "курьера": ("Кафе и рестораны", "Доставка"),
            "еда доставка": ("Кафе и рестораны", "Доставка"),

            // Продукты
            "продукты": ("Продукты", nil),
            "продуктов": ("Продукты", nil),
            "продукт": ("Продукты", nil),
            "магазин": ("Продукты", nil),
            "маркет": ("Продукты", nil),
            "супермаркет": ("Продукты", nil),
            "гипермаркет": ("Продукты", nil),

            // Покупки
            "шопинг": ("Одежда", nil),
            "одежда": ("Одежда", nil),
            "обувь": ("Одежда", "Обувь"),

            // Развлечения
            "кино": ("Развлечения", nil),
            "театр": ("Развлечения", nil),
            "концерт": ("Развлечения", nil),
            "развлечения": ("Развлечения", nil),

            // Здоровье
            "аптека": ("Здоровье", "Аптека"),
            "лекарство": ("Здоровье", "Аптека"),
            "врач": ("Здоровье", "Врач"),
            "больница": ("Здоровье", "Врач"),
            "стоматолог": ("Здоровье", "Стоматолог"),

            // Коммунальные
            "коммунальные": ("Коммунальные", nil),
            "квартплата": ("Коммунальные", nil),
            "электричество": ("Коммунальные", "Электричество"),
            "вода": ("Коммунальные", "Вода"),
            "газ": ("Коммунальные", "Газ"),
            "интернет": ("Коммунальные", "Интернет"),
            "телефон": ("Коммунальные", "Телефон"),

            // Образование
            "образование": ("Образование", nil),
            "школа": ("Образование", nil),
            "университет": ("Образование", nil),
            "курсы": ("Образование", nil),

            // Зарплата (доход)
            "зарплата": ("Зарплата", nil),
            "зарплату": ("Зарплата", nil),
            "оклад": ("Зарплата", nil),
            "премия": ("Зарплата", nil),

            // Другое
            "услуги": ("Услуги", nil),
            "ремонт": ("Услуги", nil),

            // DE — targets are the German onboarding preset names
            // (onboarding.preset.* in de.lproj). Presets create no
            // subcategories, so all subcategory slots are nil.
            "lebensmittel": ("Lebensmittel", nil),
            "supermarkt": ("Lebensmittel", nil),
            "einkauf lebensmittel": ("Lebensmittel", nil),
            "restaurant": ("Essen gehen", nil),
            "kaffee": ("Essen gehen", nil),
            "mittagessen": ("Essen gehen", nil),
            "abendessen": ("Essen gehen", nil),
            "imbiss": ("Essen gehen", nil),
            "lieferando": ("Essen gehen", nil),
            "taxi": ("Transport", nil),
            "benzin": ("Transport", nil),
            "tanken": ("Transport", nil),
            "parken": ("Transport", nil),
            "bahn": ("Transport", nil),
            "u-bahn": ("Transport", nil),
            "bus fahren": ("Transport", nil),
            "fahrkarte": ("Transport", nil),
            "miete": ("Wohnen", nil),
            "wohnung": ("Wohnen", nil),
            "nebenkosten": ("Nebenkosten", nil),
            "strom": ("Nebenkosten", nil),
            "heizung": ("Nebenkosten", nil),
            "apotheke": ("Gesundheit", nil),
            "medikament": ("Gesundheit", nil),
            "arzt": ("Gesundheit", nil),
            "zahnarzt": ("Gesundheit", nil),
            "kleidung": ("Kleidung", nil),
            "schuhe": ("Kleidung", nil),
            "kino": ("Unterhaltung", nil),
            "konzert": ("Unterhaltung", nil),
            "unterhaltung": ("Unterhaltung", nil),
            "urlaub": ("Reisen", nil),
            "flug": ("Reisen", nil),
            "hotel": ("Reisen", nil),
            "bildung": ("Bildung", nil),
            "kurs": ("Bildung", nil),
            "geschenk": ("Geschenke", nil),
            "haustier": ("Haustiere", nil),
            "tierarzt": ("Haustiere", nil),
            "abo": ("Abos", nil),
            "abonnement": ("Abos", nil),

            // ES — targets are the Spanish onboarding preset names.
            "supermercado": ("Supermercado", nil),
            "mercado": ("Supermercado", nil),
            "comida": ("Restaurantes", nil),
            "restaurante": ("Restaurantes", nil),
            "café": ("Restaurantes", nil),
            "gasolina": ("Transporte", nil),
            "transporte": ("Transporte", nil),
            "alquiler": ("Vivienda", nil),
            "renta": ("Vivienda", nil),
            "luz": ("Servicios públicos", nil),
            "farmacia": ("Salud", nil),
            "médico": ("Salud", nil),
            "ropa": ("Ropa", nil),
            "zapatos": ("Ropa", nil),
            "cine": ("Entretenimiento", nil),
            "concierto": ("Entretenimiento", nil),
            "vuelo": ("Viajes", nil),
            "viaje": ("Viajes", nil),
            "regalo": ("Regalos", nil),
            "mascota": ("Mascotas", nil),
            "veterinario": ("Mascotas", nil),
            "suscripción": ("Suscripciones", nil),

            // FR — targets are the French onboarding preset names.
            "courses": ("Courses", nil),
            "supermarché": ("Courses", nil),
            "resto": ("Restaurants", nil),
            "essence": ("Transports", nil),
            "métro": ("Transports", nil),
            "loyer": ("Logement", nil),
            "électricité": ("Charges", nil),
            "pharmacie": ("Santé", nil),
            "médecin": ("Santé", nil),
            "vêtements": ("Vêtements", nil),
            "chaussures": ("Vêtements", nil),
            "cinéma": ("Loisirs", nil),
            "avion": ("Voyages", nil),
            "voyage": ("Voyages", nil),
            "cadeau": ("Cadeaux", nil),
            "vétérinaire": ("Animaux", nil),

            // TR — targets are the Turkish onboarding preset names. Matching
            // is substring-based, so agglutinated forms (markete, taksiye)
            // still hit the stem ("market", "taksi"). Keys that would collide
            // with another language ("benzin" already maps to DE "Transport",
            // same concept) are intentionally omitted — a flat dict can't hold
            // one key twice, and the shared concept already resolves.
            "market": ("Market", nil),
            "restoran": ("Dışarıda yemek", nil),
            "yemek": ("Dışarıda yemek", nil),
            "kahve": ("Dışarıda yemek", nil),
            "taksi": ("Ulaşım", nil),
            "ulaşım": ("Ulaşım", nil),
            "kira": ("Konut", nil),
            "fatura": ("Faturalar", nil),
            "elektrik": ("Faturalar", nil),
            "eczane": ("Sağlık", nil),
            "doktor": ("Sağlık", nil),
            "giyim": ("Giyim", nil),
            "ayakkabı": ("Giyim", nil),
            "sinema": ("Eğlence", nil),
            "uçak": ("Seyahat", nil),
            "seyahat": ("Seyahat", nil),
            "hediye": ("Hediyeler", nil),
            "veteriner": ("Evcil hayvanlar", nil),

            // PT-BR — targets are the Brazilian onboarding preset names.
            // "restaurante"/"gasolina" already map (via ES) to the identically
            // spelled presets "Restaurantes"/"Transporte", so they serve
            // Brazilian users too and are not repeated here. "médico"/"uber"
            // are omitted to avoid duplicate keys with the ES/RU entries.
            "almoço": ("Restaurantes", nil),
            "jantar": ("Restaurantes", nil),
            "aluguel": ("Moradia", nil),
            "conta de luz": ("Contas de casa", nil),
            "farmácia": ("Saúde", nil),
            "roupa": ("Roupas", nil),
            "cinema": ("Lazer", nil),
            "viagem": ("Viagens", nil),
            "presente": ("Presentes", nil),
            "veterinário": ("Pets", nil),

            // IT — targets are the Italian onboarding preset names. Keys that
            // would duplicate another language ("farmacia" ES, "cinema" PT,
            // "regalo"/"veterinario" ES) are omitted; accent-free variants
            // ("medico" vs ES "médico") are safe distinct keys.
            "spesa": ("Spesa", nil),
            "supermercato": ("Spesa", nil),
            "ristorante": ("Ristoranti", nil),
            "pranzo": ("Ristoranti", nil),
            "cena": ("Ristoranti", nil),
            "caffè": ("Ristoranti", nil),
            "benzina": ("Trasporti", nil),
            "trasporti": ("Trasporti", nil),
            "affitto": ("Casa", nil),
            "bolletta": ("Utenze", nil),
            "bollette": ("Utenze", nil),
            "medico": ("Salute", nil),
            "abbigliamento": ("Abbigliamento", nil),
            "scarpe": ("Abbigliamento", nil),
            "film": ("Svago", nil),
            "concerto": ("Svago", nil),
            "viaggio": ("Viaggi", nil),
            "volo": ("Viaggi", nil),
            "regali": ("Regali", nil),
            "animali": ("Animali", nil),
            "abbonamento": ("Abbonamenti", nil),

            // UK — targets are the Ukrainian onboarding preset names. Keys
            // identical to a Russian entry ("бензин", "ресторан", "аптека")
            // are omitted: a flat dict can't hold one key twice, and where
            // the target preset name matches ("Транспорт" ru==uk) the Russian
            // entry already serves Ukrainian speakers.
            "продукти": ("Продукти", nil),
            "таксі": ("Транспорт", nil),
            "проїзд": ("Транспорт", nil),
            "їжа": ("Кафе та ресторани", nil),
            "кава": ("Кафе та ресторани", nil),
            "оренда": ("Житло", nil),
            "житло": ("Житло", nil),
            "комуналка": ("Комунальні послуги", nil),
            "лікар": ("Здоров'я", nil),
            "одяг": ("Одяг", nil),
            "взуття": ("Одяг", nil),
            "кіно": ("Розваги", nil),
            "розваги": ("Розваги", nil),
            "подорож": ("Подорожі", nil),
            "навчання": ("Освіта", nil),
            "подарунок": ("Подарунки", nil),
            "ветеринар": ("Домашні улюбленці", nil),
            "підписка": ("Підписки", nil),

            // FR-CA — the Quebec word for groceries.
            "épicerie": ("Courses", nil),

            // EN — targets are the English onboarding preset names. Words other
            // languages share ("restaurant", "taxi", "hotel", "cinema") are keyed once
            // above: `categoryGroups` finds the person's own category for them whatever
            // language they set up in. Short words that sit inside other words ("rent"
            // in "trente") are in `wholeWordCategoryMap`.
            "groceries": ("Groceries", nil),
            "grocery": ("Groceries", nil),
            "supermarket": ("Groceries", nil),
            "lunch": ("Dining out", nil),
            "dinner": ("Dining out", nil),
            "breakfast": ("Dining out", nil),
            "coffee": ("Dining out", nil),
            "takeout": ("Dining out", nil),
            "cafe": ("Dining out", nil),
            "gasoline": ("Transport", nil),
            "petrol": ("Transport", nil),
            "fuel": ("Transport", nil),
            "parking": ("Transport", nil),
            "subway": ("Transport", nil),
            "metro": ("Transport", nil),
            "lyft": ("Transport", nil),
            "mortgage": ("Housing", nil),
            "apartment": ("Housing", nil),
            "utilities": ("Utilities", nil),
            "electricity": ("Utilities", nil),
            "water bill": ("Utilities", nil),
            "phone bill": ("Utilities", nil),
            "internet": ("Utilities", nil),
            "pharmacy": ("Health", nil),
            "doctor": ("Health", nil),
            "dentist": ("Health", nil),
            "medicine": ("Health", nil),
            "hospital": ("Health", nil),
            "clothes": ("Clothing", nil),
            "clothing": ("Clothing", nil),
            "shoes": ("Clothing", nil),
            "movie": ("Entertainment", nil),
            "concert": ("Entertainment", nil),
            "theater": ("Entertainment", nil),
            "theatre": ("Entertainment", nil),
            "flight": ("Travel", nil),
            "airbnb": ("Travel", nil),
            "vacation": ("Travel", nil),
            "tuition": ("Education", nil),
            "school": ("Education", nil),
            "textbook": ("Education", nil),
            "gift": ("Gifts", nil),
            "birthday": ("Gifts", nil),
            "subscription": ("Subscriptions", nil),
            "netflix": ("Subscriptions", nil),
            "spotify": ("Subscriptions", nil),
            "pet food": ("Pets", nil),
            "haircut": ("Services", nil),
            "barber": ("Services", nil),
            "repair": ("Services", nil),
            "salary": ("Salary", nil),
            "paycheck": ("Salary", nil),

            // JA — targets are the Japanese onboarding preset names. Matched as
            // substrings, which suits text without spaces ("コンビニで500円").
            "スーパー": ("食費", nil),
            "コンビニ": ("食費", nil),
            "食料品": ("食費", nil),
            "食材": ("食費", nil),
            "ランチ": ("外食", nil),
            "昼食": ("外食", nil),
            "昼ご飯": ("外食", nil),
            "夕食": ("外食", nil),
            "晩ご飯": ("外食", nil),
            "朝食": ("外食", nil),
            "カフェ": ("外食", nil),
            "コーヒー": ("外食", nil),
            "レストラン": ("外食", nil),
            "居酒屋": ("外食", nil),
            "外食": ("外食", nil),
            "タクシー": ("交通", nil),
            "電車": ("交通", nil),
            "地下鉄": ("交通", nil),
            "バス代": ("交通", nil),
            "ガソリン": ("交通", nil),
            "駐車": ("交通", nil),
            "新幹線": ("交通", nil),
            "交通費": ("交通", nil),
            "家賃": ("住居", nil),
            "電気代": ("光熱費", nil),
            "ガス代": ("光熱費", nil),
            "水道代": ("光熱費", nil),
            "光熱費": ("光熱費", nil),
            "携帯代": ("光熱費", nil),
            "通信費": ("光熱費", nil),
            "薬局": ("健康", nil),
            "病院": ("健康", nil),
            "歯医者": ("健康", nil),
            "洋服": ("衣類", nil),
            "服": ("衣類", nil),
            "靴": ("衣類", nil),
            "映画": ("娯楽", nil),
            "カラオケ": ("娯楽", nil),
            "ゲーム": ("娯楽", nil),
            "コンサート": ("娯楽", nil),
            "旅行": ("旅行", nil),
            "ホテル": ("旅行", nil),
            "航空券": ("旅行", nil),
            "学費": ("教育", nil),
            "授業料": ("教育", nil),
            "塾": ("教育", nil),
            "プレゼント": ("ギフト", nil),
            "お土産": ("ギフト", nil),
            "サブスク": ("サブスク", nil),
            "ペット": ("ペット", nil),
            "動物病院": ("ペット", nil),
            "美容院": ("サービス", nil),
            "美容室": ("サービス", nil),
            "修理": ("サービス", nil),
            "クリーニング": ("サービス", nil),
            "給料": ("給与", nil),
            "給与": ("給与", nil),

            // KO — targets are the Korean onboarding preset names. "마트" is left out
            // (it sits inside "스마트폰"), and so is "약" (inside "예약", "약속").
            "장보기": ("장보기", nil),
            "식료품": ("장보기", nil),
            "슈퍼": ("장보기", nil),
            "편의점": ("장보기", nil),
            "이마트": ("장보기", nil),
            "점심": ("외식", nil),
            "저녁식사": ("외식", nil),
            "아침식사": ("외식", nil),
            "커피": ("외식", nil),
            "카페": ("외식", nil),
            "식당": ("외식", nil),
            "외식": ("외식", nil),
            "배달": ("외식", nil),
            "택시": ("교통", nil),
            "버스": ("교통", nil),
            "지하철": ("교통", nil),
            "주유": ("교통", nil),
            "기름값": ("교통", nil),
            "주차": ("교통", nil),
            "기차": ("교통", nil),
            "월세": ("주거", nil),
            "관리비": ("공과금", nil),
            "전기세": ("공과금", nil),
            "전기요금": ("공과금", nil),
            "가스비": ("공과금", nil),
            "수도세": ("공과금", nil),
            "통신비": ("공과금", nil),
            "공과금": ("공과금", nil),
            "약국": ("건강", nil),
            "병원": ("건강", nil),
            "치과": ("건강", nil),
            "옷": ("의류", nil),
            "신발": ("의류", nil),
            "영화": ("여가", nil),
            "공연": ("여가", nil),
            "콘서트": ("여가", nil),
            "게임": ("여가", nil),
            "여행": ("여행", nil),
            "호텔": ("여행", nil),
            "항공권": ("여행", nil),
            "학원": ("교육", nil),
            "학비": ("교육", nil),
            "선물": ("선물", nil),
            "넷플릭스": ("구독", nil),
            "반려동물": ("반려동물", nil),
            "동물병원": ("반려동물", nil),
            "사료": ("반려동물", nil),
            "미용실": ("서비스", nil),
            "수리": ("서비스", nil),
            "세탁": ("서비스", nil),
            "월급": ("급여", nil),
            "급여": ("급여", nil),

            // KK — targets are the Kazakh onboarding preset names. Matched as substrings, which
            // takes the suffixes ("азық-түлікке", "таксиге"). Words a Russian entry already has
            // ("кафе", "такси", "кино", "бензин") resolve through it; short stems that sit inside
            // other words are left out ("нан" is in "финансы", "ет", "ит", "тіс", "той").
            "азық-түлік": ("Азық-түлік", nil),
            "азық": ("Азық-түлік", nil),
            "дүкен": ("Азық-түлік", nil),
            "базар": ("Азық-түлік", nil),
            "сүт": ("Азық-түлік", nil),
            "көкөніс": ("Азық-түлік", nil),
            "жеміс": ("Азық-түлік", nil),
            "түскі ас": ("Кафе мен мейрамханалар", nil),
            "кешкі ас": ("Кафе мен мейрамханалар", nil),
            "таңғы ас": ("Кафе мен мейрамханалар", nil),
            "мейрамхана": ("Кафе мен мейрамханалар", nil),
            "асхана": ("Кафе мен мейрамханалар", nil),
            "кофехана": ("Кафе мен мейрамханалар", nil),
            "көлік": ("Көлік", nil),
            "жанармай": ("Көлік", nil),
            "тұрақ": ("Көлік", nil),
            "жол ақы": ("Көлік", nil),
            "пәтерақы": ("Тұрғын үй", nil),
            "пәтер": ("Тұрғын үй", nil),
            "жалдау": ("Тұрғын үй", nil),
            "коммуналдық": ("Коммуналдық", nil),
            "жарық": ("Коммуналдық", nil),
            "ұялы байланыс": ("Коммуналдық", nil),
            "байланыс": ("Коммуналдық", nil),
            "дәріхана": ("Денсаулық", nil),
            "дәрігер": ("Денсаулық", nil),
            "дәрі": ("Денсаулық", nil),
            "емхана": ("Денсаулық", nil),
            "аурухана": ("Денсаулық", nil),
            "аяқ киім": ("Киім", nil),
            "киім": ("Киім", nil),
            "ойын-сауық": ("Ойын-сауық", nil),
            "ойын": ("Ойын-сауық", nil),
            "саяхат": ("Саяхат", nil),
            "демалыс": ("Саяхат", nil),
            "ұшақ": ("Саяхат", nil),
            "қонақүй": ("Саяхат", nil),
            "оқу": ("Білім", nil),
            "мектеп": ("Білім", nil),
            "кітап": ("Білім", nil),
            "сыйлық": ("Сыйлықтар", nil),
            "туған күн": ("Сыйлықтар", nil),
            "жазылым": ("Жазылымдар", nil),
            "мысық": ("Үй жануарлары", nil),
            "жануар": ("Үй жануарлары", nil),
            "шаштараз": ("Қызметтер", nil),
            "жөндеу": ("Қызметтер", nil),
            "тазалау": ("Қызметтер", nil),
            "жалақы": ("Жалақы", nil),
            "сыйақы": ("Жалақы", nil),
            "кіріс": ("Басқа кірістер", nil),
            "табыс": ("Басқа кірістер", nil)
        ]

    /// Short keywords matched as whole words only: as substrings they fire
    /// inside unrelated words ("rent" in "parent", "bus" in "business", "bar"
    /// in "barber", "vet" in Turkish "evet"). Kept apart from `categoryMap`,
    /// whose keys match anywhere in the text.
    private lazy var wholeWordCategoryMap: [String: (category: String, subcategory: String?)] = [
        "rent": ("Housing", nil),
        "gas": ("Transport", nil),
        "bus": ("Transport", nil),
        "cab": ("Transport", nil),
        "bar": ("Dining out", nil),
        "trip": ("Travel", nil),
        "vet": ("Pets", nil)
    ]

    private struct CategoryKeyword {
        let key: String
        let wholeWord: Bool
    }

    /// The keys of both maps, longest first so longer phrases ("еда доставка")
    /// win over their substrings ("еда") and "medicine" over "cine"; equal
    /// lengths go alphabetically. Without that total order the same phrase
    /// could pick a different category on each launch, because `Dictionary`
    /// order is randomized per process. Computed once.
    private lazy var sortedCategoryKeys: [CategoryKeyword] =
        (categoryMap.keys.map { CategoryKeyword(key: $0, wholeWord: false) }
            + wholeWordCategoryMap.keys.map { CategoryKeyword(key: $0, wholeWord: true) })
        .sorted { $0.key.count != $1.key.count ? $0.key.count > $1.key.count : $0.key < $1.key }

    private func categoryEntry(_ keyword: CategoryKeyword) -> (category: String, subcategory: String?)? {
        keyword.wholeWord ? wholeWordCategoryMap[keyword.key] : categoryMap[keyword.key]
    }

    private func matches(_ keyword: CategoryKeyword, in text: String) -> Bool {
        keyword.wholeWord ? Self.containsWord(keyword.key, in: text) : text.contains(keyword.key)
    }

    /// Whether `word` occurs in `text` with no letter right before or after it.
    /// `\b` can't be used: it sees no boundary between a CJK character and a digit.
    static func containsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let letterBefore = range.lowerBound > text.startIndex
                && text[text.index(before: range.lowerBound)].isLetter
            let letterAfter = range.upperBound < text.endIndex && text[range.upperBound].isLetter
            if !letterBefore && !letterAfter { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    /// Each onboarding preset under its name in every app language
    /// (`onboarding.preset.*`; `VoiceCategoryTargetsTests` pins the groups to
    /// the strings files). A keyword targets one language's name ("Groceries",
    /// "食費"), while the user's categories carry the names of the language
    /// they onboarded in, so the target resolves through its group: "groceries"
    /// lands in "Продукты" for someone whose categories are Russian.
    static let categoryGroups: [[String]] = [
        ["Groceries", "Продукты", "Lebensmittel", "Supermercado", "Courses", "Market", "Mercado", "Spesa", "Продукти", "食費", "장보기", "Азық-түлік"],
        ["Dining out", "Кафе и рестораны", "Essen gehen", "Restaurantes", "Restaurants", "Dışarıda yemek", "Ristoranti", "Кафе та ресторани", "外食", "외식", "Кафе мен мейрамханалар"],
        ["Transport", "Транспорт", "Transporte", "Transports", "Ulaşım", "Trasporti", "交通", "교통", "Көлік"],
        ["Housing", "Жильё", "Wohnen", "Vivienda", "Logement", "Konut", "Moradia", "Casa", "Житло", "住居", "주거", "Тұрғын үй"],
        ["Utilities", "Коммунальные", "Nebenkosten", "Servicios públicos", "Charges", "Faturalar", "Contas de casa", "Utenze", "Комунальні послуги", "光熱費", "공과금", "Коммуналдық"],
        ["Health", "Здоровье", "Gesundheit", "Salud", "Santé", "Sağlık", "Saúde", "Salute", "Здоров'я", "健康", "건강", "Денсаулық"],
        ["Clothing", "Одежда", "Kleidung", "Ropa", "Vêtements", "Giyim", "Roupas", "Abbigliamento", "Одяг", "衣類", "의류", "Киім"],
        ["Entertainment", "Развлечения", "Unterhaltung", "Entretenimiento", "Loisirs", "Eğlence", "Lazer", "Svago", "Розваги", "娯楽", "여가", "Ойын-сауық"],
        ["Travel", "Путешествия", "Reisen", "Viajes", "Voyages", "Seyahat", "Viagens", "Viaggi", "Подорожі", "旅行", "여행", "Саяхат"],
        ["Education", "Образование", "Bildung", "Educación", "Éducation", "Eğitim", "Educação", "Istruzione", "Освіта", "教育", "교육", "Білім"],
        ["Gifts", "Подарки", "Geschenke", "Regalos", "Cadeaux", "Hediyeler", "Presentes", "Regali", "Подарунки", "ギフト", "선물", "Сыйлықтар"],
        ["Subscriptions", "Подписки", "Abos", "Suscripciones", "Abonnements", "Abonelikler", "Assinaturas", "Abbonamenti", "Підписки", "サブスク", "구독", "Жазылымдар"],
        ["Pets", "Питомцы", "Haustiere", "Mascotas", "Animaux", "Evcil hayvanlar", "Animali", "Домашні улюбленці", "ペット", "반려동물", "Үй жануарлары"],
        ["Services", "Услуги", "Dienstleistungen", "Servicios", "Hizmetler", "Serviços", "Servizi", "Послуги", "サービス", "서비스", "Қызметтер"],
        ["Other", "Прочее", "Sonstiges", "Otros", "Autre", "Diğer", "Outros", "Altro", "Інше", "その他", "기타", "Басқа"],
        ["Salary", "Зарплата", "Gehalt", "Salario", "Salaire", "Maaş", "Salário", "Stipendio", "給与", "급여", "Жалақы"],
        ["Other income", "Прочие доходы", "Sonstige Einnahmen", "Otros ingresos", "Autres revenus", "Diğer gelirler", "Outras receitas", "Altre entrate", "Інші доходи", "その他の収入", "기타 수입", "Басқа кірістер"]
    ]

    private static let categoryGroupByName: [String: [String]] = {
        var result: [String: [String]] = [:]
        for group in categoryGroups {
            for name in group { result[categoryNameKey(name)] = group }
        }
        return result
    }()

    /// Comparison key for category names: case and "ё" don't matter.
    private static func categoryNameKey(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The user's category named `name`, ignoring case and "ё".
    private func liveCategoryName(_ name: String) -> String? {
        let key = Self.categoryNameKey(name)
        return liveCategories.first { Self.categoryNameKey($0.name) == key }?.name
    }

    /// The user's category for a keyword target: the target itself when the
    /// user has it, else the same preset under another language's name, else
    /// the target unchanged.
    private func resolveCategoryName(_ target: String) -> String {
        if let own = liveCategoryName(target) { return own }
        for name in Self.categoryGroupByName[Self.categoryNameKey(target)] ?? [] {
            if let own = liveCategoryName(name) { return own }
        }
        return target
    }

    /// Income keywords for entity detection — cached
    private lazy var incomeKeywords: [String] =
        ["пришло", "пришел", "пришла", "получил", "получила", "получил", "зачисление", "доход", "зарплата"]

    /// Expense keywords for entity detection — cached
    private lazy var expenseKeywords: [String] =
        ["потратил", "потратила", "купил", "купила", "оплатил", "оплатила", "расход", "списали"]

    // MARK: - Pre-compiled регулярные выражения для производительности

    /// A written amount: grouped thousands ("12,000", "1.234,56", "10 000")
    /// or a plain number with up to two decimals ("1500", "12,50").
    /// `decimalAmount` reads which separator is the decimal one.
    private static let amountPattern = #"\d{1,3}(?:[\s,.]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?"#

    /// Currency words and signs that make a neighbouring number an amount.
    private static let amountCurrencyTokens = #"тенге|теңге|тг|₸|доллар|долларов|\$|usd|евро|еуро|eur|€|рубл|rub|₽|円|¥|원|₩|₺|₴"#

    /// Capture group 1 is the number in every pattern. Digit lookarounds
    /// replace `\b`, which finds no boundary between a digit and CJK text
    /// ("500円", "コンビニで500").
    private let amountRegexes: [NSRegularExpression] = {
        let number = "((?:" + VoiceInputParser.amountPattern + "))"
        let currency = "(?:" + VoiceInputParser.amountCurrencyTokens + ")"
        let patterns = [
            // Валюта перед числом
            currency + #"\s*"# + number + #"(?![\p{N}])"#,
            // Валюта после числа
            #"(?<![\p{N}.,])"# + number + #"\s*"# + currency,
            // Просто число (ищем самое большое число)
            #"(?<![\p{N}.,])"# + number + #"(?![\p{N}])"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private let accountPatternRegexes: [NSRegularExpression] = {
        let patterns = [
            #"со\s+счета\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"со\s+счёта\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"с\s+карты\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"с\s+([^,\s]+(?:\s+[^,\s]+)*)\s+счета"#,
            #"с\s+([^,\s]+(?:\s+[^,\s]+)*)\s+счёта"#,
            #"карта\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"счет\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"счёт\s+([^,\s]+(?:\s+[^,\s]+)*)"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    // Словарь замен для нормализации
    private let textReplacements: [String: String] = [
        // Варианты "со счета"
        "со счёта": "со счета",
        "с счета": "со счета",
        "с счёта": "со счета",
        // Варианты валюты
        "тэг": "тг",
        "тенга": "тг",
        "тенг": "тг",
        // Бренды/счета
        "каспи": "kaspi",
        "каспи банк": "kaspi",
        "kaspi bank": "kaspi",
        "халик": "halyk",
        "халик банк": "halyk",
        "halyk bank": "halyk",
        "алатау": "alatau",
        "алатау сити": "alatau",
        "alatau city": "alatau",
        "хом кредит": "home credit",
        "хомкредит": "home credit",
        "home credit bank": "home credit",
        "жусан": "jusan",
        "jusan bank": "jusan"
    ]
    
    // Алиасы для счетов
    private let accountAliases: [String: [String]] = [
        "kaspi": ["каспи", "kaspi", "каспи банк", "kaspi bank", "каспи карта"],
        "halyk": ["halyk", "халик", "halyk bank", "халик банк", "халик карта"],
        "alatau": ["alatau", "алатау", "alatau city", "алатау сити", "алатау карта"],
        "home credit": ["home credit", "хом кредит", "хомкредит", "home credit bank"],
        "jusan": ["jusan", "жусан", "jusan bank", "жусан банк"],
        "gold": ["gold", "голд", "gold card", "голд карта"]
    ]
    
    // Стоп-слова для поиска счета
    private let stopWords: Set<String> = ["с", "со", "счет", "счёта", "счета", "карта", "карты", "банк", "банка"]
    
    // Словарь для распознавания чисел словами
    private let numberWords: [String: Int] = [
        "ноль": 0, "нуль": 0,
        "один": 1, "одна": 1, "одно": 1,
        "два": 2, "две": 2,
        "три": 3,
        "четыре": 4,
        "пять": 5,
        "шесть": 6,
        "семь": 7,
        "восемь": 8,
        "девять": 9,
        "десять": 10,
        "одиннадцать": 11,
        "двенадцать": 12,
        "тринадцать": 13,
        "четырнадцать": 14,
        "пятнадцать": 15,
        "шестнадцать": 16,
        "семнадцать": 17,
        "восемнадцать": 18,
        "девятнадцать": 19,
        "двадцать": 20,
        "тридцать": 30,
        "сорок": 40,
        "пятьдесят": 50,
        "шестьдесят": 60,
        "семьдесят": 70,
        "восемьдесят": 80,
        "девяносто": 90,
        "сто": 100,
        "двести": 200,
        "триста": 300,
        "четыреста": 400,
        "пятьсот": 500,
        "шестьсот": 600,
        "семьсот": 700,
        "восемьсот": 800,
        "девятьсот": 900,
        "тысяча": 1000, "тысячи": 1000, "тысяч": 1000,
        // Colloquial sibling — very common in speech.
        "тыща": 1000, "тыщи": 1000, "тыщ": 1000,
        // KK. Hundreds multiply ("екі жүз" is 200, parseAmountFromWords). "он" (10) is the
        // Russian "he", so it counts only in Kazakh (Self.kazakhOnlyNumberWords).
        "бір": 1, "екі": 2, "үш": 3, "төрт": 4, "бес": 5, "алты": 6, "жеті": 7, "сегіз": 8,
        "тоғыз": 9, "он": 10, "жиырма": 20, "отыз": 30, "қырық": 40, "елу": 50, "алпыс": 60,
        "жетпіс": 70, "сексен": 80, "тоқсан": 90, "жүз": 100, "мың": 1000,
    ]

    /// Number words that are ordinary words in another app language: "он" is "he" in Russian.
    private static let kazakhOnlyNumberWords: Set<String> = ["он"]

    /// The app runs in Kazakh (as FR "hier" in `parseDate`, by the current locale's language).
    private static var appSpeaksKazakh: Bool {
        Locale.current.language.languageCode?.identifier == "kk"
    }

    /// A number with a thousand word after it ("5 тысяч", "2,5 мың", "10 мыңға") as digits, so
    /// the amount regexes read 5000, not 5. The word keeps no suffix: "мыңға" goes with it.
    private static let thousandWordRegex = try? NSRegularExpression(
        pattern: #"(?<![\p{N}.,])(\d+(?:[.,]\d{1,3})?)\s*(?:тысяч\p{L}*|тыщ\p{L}*|тыс(?![\p{L}])\.?|мың\p{L}*)"#
    )

    static func expandThousandWords(_ text: String) -> String {
        guard let regex = thousandWordRegex else { return text }
        var result = text
        let source = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let number = source.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            guard let value = Decimal(string: number), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: NSDecimalNumber(decimal: value * 1000).stringValue)
        }
        return result
    }
    
    // MARK: - Initialization

    /// Initializes parser with live references to ViewModels
    /// - Parameters:
    ///   - categoriesViewModel: ViewModel managing categories and subcategories
    ///   - accountsViewModel: ViewModel managing accounts
    ///   - transactionsViewModel: ViewModel managing transactions (for smart defaults)
    init(
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionsViewModel: TransactionsViewModel
    ) {
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
    }
    
    func parse(_ text: String) -> ParsedOperation {
        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif

        let normalizedText = normalizeText(text)

        // Compute default account once per parse() — avoids iterating all transactions multiple times
        cachedDefaultAccount = getSmartDefaultAccount()
        cachedDefaultsByCategory.removeAll(keepingCapacity: true)

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif

        var operation = ParsedOperation(note: text)
        
        // 1. Определяем дату
        operation.date = parseDate(from: normalizedText)
        
        // 2. Определяем тип операции
        operation.type = parseType(from: normalizedText)
        
        // 3. Извлекаем сумму
        operation.amount = parseAmount(from: normalizedText)
        
        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            if operation.amount != nil {
            } else {
            }
        }
        #endif

        // 4. Ищем счет (до валюты: "$" и "dollars" читаются в валюте счета)
        let accountResult = findAccount(from: normalizedText)
        operation.accountId = accountResult.accountId

        // 5. Извлекаем валюту
        operation.currencyCode = parseCurrency(from: normalizedText, accountId: operation.accountId)

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            if let accountId = accountResult.accountId,
               let _ = liveAccounts.first(where: { $0.id == accountId }) {
                _ = accountId  // Debug log placeholder
            }
        }
        #endif

        // 6. Определяем категорию и подкатегории
        let (category, subcats, categoryIsGuess) = parseCategory(from: normalizedText)
        operation.categoryName = category
        operation.subcategoryNames = subcats
        operation.categoryIsGuess = categoryIsGuess

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            _ = category ?? ""  // Debug log placeholder
        }
        #endif
        
        // Если валюта не найдена, используем валюту найденного счета или счета по умолчанию
        if operation.currencyCode == nil {
            if let accountId = operation.accountId,
               let account = liveAccounts.first(where: { $0.id == accountId }) {
                operation.currencyCode = account.currency
            } else if let cachedDefaultAccount = cachedDefaultAccount {
                operation.currencyCode = cachedDefaultAccount.currency
            } else {
                operation.currencyCode = "KZT" // По умолчанию тенге
            }
        }
        
        // Если счет не найден, используем счет с учётом категории. Сначала
        // спрашиваем learning-store, затем usage-tracker — и только потом
        // глобальный дефолт. Каждая ступень дополнительно прогоняется через
        // фильтр regular-аккаунтов, чтобы депозит/кредит никогда не попал
        // в превью голосовой транзакции.
        operation.accountId = regularAccountId(operation.accountId)
            ?? regularAccountId(smartDefaultAccount(forCategory: operation.categoryName)?.id)
            ?? regularAccountId(cachedDefaultAccount?.id)
            ?? liveAccounts.first(where: { !$0.isLoan && !$0.isDeposit })?.id
        if operation.currencyCode == nil,
           let id = operation.accountId,
           let account = liveAccounts.first(where: { $0.id == id }) {
            operation.currencyCode = account.currency
        }

        return operation
    }

    /// Returns `id` only if it points to a regular (non-loan, non-deposit)
    /// account that still exists in the live list. Used as a uniform filter
    /// at every account-resolution fallback so voice quick-save never
    /// targets credit lines or savings deposits.
    private func regularAccountId(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        guard let account = liveAccounts.first(where: { $0.id == id }) else { return nil }
        guard !account.isLoan, !account.isDeposit else { return nil }
        return id
    }

    /// Parses one or more operations from a single utterance.
    /// Splits the text into clauses via `VoiceInputSegmenter`, parses each in
    /// isolation, then forward-fills inherited fields (currency, account,
    /// type) from the previous clause. Returns an empty array if no clause
    /// contains a recognizable amount.
    func parseMulti(_ text: String) -> [ParsedOperation] {
        let clauses = VoiceInputSegmenter.segment(text)
        guard !clauses.isEmpty else { return [] }

        // Compute global default once for the whole utterance — used when the
        // category-aware lookup has nothing to say. Cleared after the loop so
        // we never carry stale state into a subsequent call.
        cachedDefaultAccount = getSmartDefaultAccount(forCategory: nil)
        cachedDefaultsByCategory.removeAll(keepingCapacity: true)
        defer {
            cachedDefaultAccount = nil
            cachedDefaultsByCategory.removeAll(keepingCapacity: true)
        }

        var operations: [ParsedOperation] = []
        var lastType: TransactionType = .expense
        var lastCurrency: String?
        var lastAccountId: String?

        for clause in clauses {
            let normalized = normalizeText(clause)

            guard let amount = parseAmount(from: normalized) else {
                // No amount in this clause — drop it. Forward-fill state is
                // unchanged so subsequent clauses still inherit from the
                // last *valid* operation.
                continue
            }

            let explicitType = parseTypeOptional(from: normalized)
            let explicitAccountId = findAccount(from: normalized).accountId
            let explicitCurrency = parseCurrency(from: normalized, accountId: explicitAccountId ?? lastAccountId)
            let (categoryName, subcategoryNames, categoryIsGuess) = parseCategory(from: normalized)

            // Per-category smart default: prefer the account most-used for
            // this category (or the user's confirmed preference, if any).
            let categoryDefault = smartDefaultAccount(forCategory: categoryName)

            let type = explicitType ?? lastType
            // Continuity wins inside one utterance: if the previous clause
            // landed on a regular account, the next clause stays on it
            // unless the user explicitly named a different one. Only when
            // there's no prior clause do we fall to the category-default.
            // Every candidate is run through `regularAccountId` so a
            // loan/deposit can never survive the cascade.
            let accountId = regularAccountId(explicitAccountId)
                ?? regularAccountId(lastAccountId)
                ?? regularAccountId(categoryDefault?.id)
                ?? regularAccountId(cachedDefaultAccount?.id)
                ?? liveAccounts.first(where: { !$0.isLoan && !$0.isDeposit })?.id
            let currency = explicitCurrency
                ?? lastCurrency
                ?? liveAccounts.first(where: { $0.id == accountId })?.currency
                ?? cachedDefaultAccount?.currency
                ?? "KZT"

            var op = ParsedOperation(note: clause)
            op.date = parseDate(from: normalized)
            op.type = type
            op.amount = amount
            op.currencyCode = currency
            op.accountId = accountId
            op.categoryName = categoryName
            op.subcategoryNames = subcategoryNames
            op.categoryIsGuess = categoryIsGuess

            operations.append(op)

            lastType = type
            lastCurrency = currency
            lastAccountId = accountId
        }

        return operations
    }

    // MARK: - Private Methods
    
    private func normalizeText(_ text: String) -> String {
        var normalized = Self.expandThousandWords(Self.expandCJKNumerals(text.lowercased()))
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Применяем замены
        for (from, to) in textReplacements {
            normalized = normalized.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        
        // Collapse spaces (убираем множественные пробелы)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Japanese and Korean amounts mix digits with the units 億/억 (10^8),
    /// 万/만 (10^4), 千/천, 百/백: "1万2000円", "1만 2천 원", "3千500". This
    /// rewrites such a span as plain digits ("12000円") so the amount regexes
    /// read it. A unit with no digit before it is left alone ("千葉"), unless
    /// it stands right before 円/원: "만원" is 10 000 won, "百円" is 100 yen.
    static func expandCJKNumerals(_ text: String) -> String {
        guard text.contains(where: { cjkUnitValues[$0] != nil }) else { return text }
        var result = text
        // Replace right to left so earlier ranges stay valid.
        for regex in [cjkNumeralRegex, cjkBareUnitRegex] {
            let source = result as NSString
            for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() {
                let span = source.substring(with: match.range(at: 1))
                guard let value = cjkNumeralValue(span),
                      let range = Range(match.range(at: 1), in: result) else { continue }
                result.replaceSubrange(range, with: NSDecimalNumber(decimal: value).stringValue)
            }
        }
        return result
    }

    private static let cjkUnitValues: [Character: Decimal] = [
        "億": 100_000_000, "억": 100_000_000,
        "万": 10_000, "만": 10_000,
        "千": 1_000, "천": 1_000,
        "百": 100, "백": 100
    ]

    /// A digit, a unit, then more digit-unit pairs and optional trailing digits,
    /// with at most one space between parts: "1万2000", "1만 2천", "1.5万".
    private static let cjkNumeralRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{N}.,])(\d+(?:[.,]\d+)?\s?[億억万만千천百백](?:\s?\d+(?:[.,]\d+)?\s?[億억万만千천百백]|\s?[億억万만千천百백])*(?:\s?\d+)?)(?![\p{N}])"#
    )

    /// Units with no digit before them, right before 円/원: "만원", "百円".
    private static let cjkBareUnitRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{N}])([億억万만千천百백]+)(?=\s?[円원])"#
    )

    /// Sums a span of digits and units: small units (千, 百) build a section,
    /// a big unit (万, 億) multiplies everything since the last big unit.
    private static func cjkNumeralValue(_ span: String) -> Decimal? {
        var total: Decimal = 0
        var section: Decimal = 0
        var number: Decimal?
        var digits = ""
        func flushDigits() {
            guard !digits.isEmpty else { return }
            number = decimalAmount(digits)
            digits = ""
        }
        for character in span {
            // Units first: `Character.isNumber` is true for 万, 千 and 百 too.
            if let unit = cjkUnitValues[character] {
                flushDigits()
                if unit >= 10_000 {
                    let coefficient = section + (number ?? 0)
                    total += (coefficient == 0 ? 1 : coefficient) * unit
                    section = 0
                } else {
                    section += (number ?? 1) * unit
                }
                number = nil
            } else if character.isASCII && (character.isNumber || character == "." || character == ",") {
                digits.append(character)
            } else {
                flushDigits()
            }
        }
        flushDigits()
        total += section + (number ?? 0)
        return total > 0 ? total : nil
    }

    // 1. Парсинг даты
    private func parseDate(from text: String) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // "позавчера"/"vorgestern"/"anteayer"/"avant-hier" contain
        // "вчера"/"gestern"/"ayer"/"hier" as substrings, so the
        // day-before-yesterday check MUST run first.
        // CJK date words (ja/ko) match via `contains()` even without spaces,
        // so they are safe to add ahead of the full voice tokenization spike.
        // 一昨日 contains 昨日, so day-before-yesterday stays first.
        let dayBeforeYesterday = ["позавчера", "vorgestern", "day before yesterday",
                                  "anteayer", "antier", "avant-hier",
                                  "anteontem", "evvelsi gün", "önceki gün",
                                  "позавчора", "l'altro ieri", "avantieri", "алдыңғы күні",
                                  "一昨日", "おととい", "그저께", "그제"]
        var yesterday = ["вчера", "yesterday", "gestern", "ayer", "ontem", "dün",
                         "вчора", "учора", "ieri", "кеше",
                         "昨日", "きのう", "어제"]
        let todayWords = ["сегодня", "today", "heute", "hoy", "aujourd'hui",
                          "hoje", "bugün", "сьогодні", "oggi", "бүгін",
                          "今日", "きょう", "오늘"]

        // FR "hier" is a homograph of DE "hier" ("here"), so it only counts
        // as a date keyword when the app runs in French.
        if Locale.current.language.languageCode?.identifier == "fr" {
            yesterday.append("hier")
        }

        if dayBeforeYesterday.contains(where: { text.contains($0) }) {
            return calendar.date(byAdding: .day, value: -2, to: today) ?? today
        } else if todayWords.contains(where: { text.contains($0) }) {
            return today
        } else if yesterday.contains(where: { text.contains($0) }) {
            return calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        return today
    }
    
    /// Tokens that map a preceding number to "× 1000" in word-form parsing.
    /// Includes both proper "тысяча/тысячи/тысяч" and colloquial "тыща/тыщи/тыщ".
    private static let thousandTokens: Set<String> = [
        "тысяча", "тысячи", "тысяч", "мың",
        "тыща", "тыщи", "тыщ",
    ]

    /// Verbs that mark a clause as an expense.
    private static let expenseKeywords: [String] = [
        "потратил", "потратила", "потратили", "потратило",
        "заплатил", "заплатила", "заплатили", "заплатило",
        "купил", "купила", "купили", "купило",
        "расход", "расходы",
        "оплатил", "оплатила", "оплатили",
        "списал", "списала", "списали",
        "покупка", "покупки",
        // EN — "paid" is intentionally absent: it is a substring of the income
        // phrase "got paid" and expense is checked first, so including "paid"
        // here would cause "got paid 500" to be classified as expense.
        "spent", "bought", "purchase", "expense",
        // DE — "bezahlt" is included even though the income phrase
        // "bezahlt bekommen" contains it (expense wins). German speakers
        // overwhelmingly say "Gehalt bekommen/erhalten" for income, so the
        // common expense phrasing takes priority.
        "ausgegeben", "gekauft", "bezahlt", "gezahlt",
        "ausgabe", "ausgaben", "einkauf", "abgebucht",
        // ES
        "gasté", "gastado", "compré", "comprado", "pagué", "pagado",
        "gasto", "gastos", "compra de",
        // FR
        "dépensé", "acheté", "payé", "dépense", "dépenses", "achat",
        // TR — bare "aldım" is deliberately absent: it means both "bought"
        // and "received" ("maaş aldım"); ambiguous phrases fall through to
        // the .expense default, while income wins via "maaş"/"gelir".
        "harcadım", "ödedim", "harcama", "gider", "satın",
        // PT-BR
        "gastei", "comprei", "paguei", "despesa", "despesas", "parcelei",
        // IT — "speso" (spent) also matches "fare la spesa" (grocery shopping)
        // but both are expenses, so no misclassification.
        "speso", "comprato", "pagato", "spesa", "spese", "acquisto",
        // UK
        "витратив", "витратила", "купив", "купила", "заплатив", "заплатила",
        "витрата", "витрати", "оплатив", "оплатила",
        // KK — bare "алдым" is absent for the Turkish reason: "bought" and "received".
        "жұмсадым", "жұмсадық", "жұмсады", "төледім", "төледік", "төледі",
        "сатып алдым", "сатып алдық", "шығын", "шығыс",
    ]

    /// Verbs that mark a clause as income.
    private static let incomeKeywords: [String] = [
        "получил", "получила", "получили", "получило",
        "пришло", "пришла", "пришли",
        "заработал", "заработала", "заработали",
        "доход", "доходы",
        "пополнил", "пополнила", "пополнили",
        "пополнение", "пополнения",
        "начислил", "начислила", "начислили",
        "зарплата", "зарплату", "зарплаты",
        "оклад", "премия", "премию",
        // EN
        "received", "earned", "income", "salary", "got paid",
        // DE
        "erhalten", "bekommen", "verdient",
        "einnahme", "einnahmen", "einkommen",
        "gehalt", "lohn", "gutschrift", "eingegangen", "bonus",
        // ES
        "recibí", "recibido", "cobré", "cobrado",
        "ingreso", "ingresos", "sueldo", "salario", "nómina", "gané",
        // FR — "versé" intentionally absent: ambiguous between paying out
        // and being paid (see docs/archive/localization-2026-07/fr-FR.md).
        "reçu", "salaire", "touché", "gagné", "revenu", "revenus",
        // TR
        "maaş", "gelir", "kazandım",
        // PT-BR
        "recebi", "ganhei", "salário", "salario", "receita",
        // IT
        "ricevuto", "stipendio", "incassato", "guadagnato", "entrata", "entrate",
        // UK
        "отримав", "отримала", "зарплата", "зарплату",
        "дохід", "надійшло", "заробив", "заробила",
        // KK
        "жалақы", "кіріс", "табыс", "сыйақы", "ақша түсті", "түсті",
    ]

    // 2. Парсинг типа операции
    private func parseType(from text: String) -> TransactionType {
        parseTypeOptional(from: text) ?? .expense
    }

    /// Same matcher as `parseType` but returns `nil` when no expense/income
    /// keyword was present. Used by `parseMulti` so subsequent clauses can
    /// inherit the type from the previous clause instead of always
    /// defaulting to `.expense`.
    private func parseTypeOptional(from text: String) -> TransactionType? {
        for keyword in Self.expenseKeywords where text.contains(keyword) {
            return .expense
        }
        for keyword in Self.incomeKeywords where text.contains(keyword) {
            return .income
        }
        return nil
    }
    
    // 3. Парсинг суммы (с поддержкой слов)
    private func parseAmount(from text: String) -> Decimal? {
        // Структура для хранения найденных сумм с приоритетом
        struct AmountMatch {
            let amount: Decimal
            let priority: Int  // 0 = с валютой (высший), 1 = без валюты (низший)
            let position: Int  // Позиция в тексте для разрешения конфликтов
            let isLikelyYear: Bool  // Похоже на год — выбирается в последнюю очередь, но НЕ отбрасывается
        }

        var foundAmounts: [AmountMatch] = []

        // Используем pre-compiled regex для производительности
        for (index, regex) in amountRegexes.enumerated() {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    if let amount = Self.decimalAmount(String(text[range])) {
                        // Приоритет: паттерны с валютой (0-1) имеют больший приоритет, чем просто числа (2)
                        let priority = index <= 1 ? 0 : 1
                        let position = match.range(at: 1).location

                        if amount >= VoiceInputConstants.minAmountValue && amount <= VoiceInputConstants.maxAmountValue {
                            // Год обычно 1900-2100 и без валюты. Раньше такие
                            // числа отбрасывались — но "2000 на такси" (типичная
                            // сумма в тенге) тогда терялась, и голосовой ввод
                            // молча ничего не создавал. Теперь год лишь
                            // понижается в приоритете: реальная сумма в той же
                            // фразе всё равно побеждает, а одинокое "2000"
                            // остаётся суммой.
                            let looksLikeYear = amount >= 1900 && amount <= 2100 && priority == 1
                            foundAmounts.append(AmountMatch(amount: amount, priority: priority, position: position, isLikelyYear: looksLikeYear))
                        }
                    }
                }
            }
        }

        // Сортируем: сначала по приоритету (валюта = лучше), затем НЕ-год
        // раньше года (чтобы реальная сумма побеждала год), потом по сумме.
        foundAmounts.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.isLikelyYear != rhs.isLikelyYear {
                return !lhs.isLikelyYear  // false (не год) идёт первым
            }
            return lhs.amount > rhs.amount
        }

        // Берем лучший результат
        if let bestMatch = foundAmounts.first {
            let rounded = (bestMatch.amount as NSDecimalNumber).rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif

            return rounded as Decimal
        }

        // Если не нашли через regex, пытаемся распознать словами
        return parseAmountFromWords(text)
    }
    
    /// Reads a written amount whatever the separators: the last group is
    /// decimals when it has one or two digits ("12,50", "1.234,56"),
    /// otherwise every separator groups thousands ("12,000", "1.500", "10 000").
    static func decimalAmount(_ written: String) -> Decimal? {
        let compact = written.unicodeScalars
            .filter { !CharacterSet.whitespaces.contains($0) }
            .map(String.init).joined()
        let parts = compact.split(whereSeparator: { $0 == "," || $0 == "." }).map(String.init)
        guard let last = parts.last,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        if parts.count > 1, last.count <= 2 {
            return Decimal(string: parts.dropLast().joined() + "." + last)
        }
        return Decimal(string: parts.joined())
    }

    // Парсинг суммы словами (до 9999)
    private func parseAmountFromWords(_ text: String) -> Decimal? {
        let words = text.components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        
        var result = 0
        var currentNumber = 0
        var hasThousand = false
        
        for word in words {
            let lowercased = word.lowercased()
            
            // "он" counts as 10 only in Kazakh: in Russian it is "he".
            if Self.kazakhOnlyNumberWords.contains(lowercased), !Self.appSpeaksKazakh { continue }
            if let number = numberWords[lowercased] {
                if number == 1000 {
                    if currentNumber > 0 {
                        result += currentNumber * 1000
                        currentNumber = 0
                    } else {
                        result += 1000
                    }
                    hasThousand = true
                } else if number == 100, currentNumber > 0, currentNumber < 10 {
                    // Kazakh hundreds multiply: "екі жүз" is 200, "бес жүз" 500.
                    currentNumber *= 100
                } else if number >= 100 {
                    if currentNumber > 0 {
                        result += currentNumber
                    }
                    currentNumber = number
                } else if number >= 10 {
                    if currentNumber >= 100 {
                        currentNumber += number
                    } else {
                        if currentNumber > 0 {
                            result += currentNumber
                        }
                        currentNumber = number
                    }
                } else {
                    if currentNumber >= 10 {
                        currentNumber += number
                    } else {
                        currentNumber = currentNumber * 10 + number
                    }
                }
            } else if Self.thousandTokens.contains(lowercased) {
                if currentNumber > 0 {
                    result += currentNumber * 1000
                    currentNumber = 0
                } else if result == 0 {
                    result = 1000
                }
                hasThousand = true
            }
        }
        
        if currentNumber > 0 {
            if hasThousand {
                result += currentNumber
            } else {
                result += currentNumber
            }
        }
        
        if result > 0 && result <= VoiceInputConstants.maxWordNumberValue {
            return Decimal(result)
        }

        return nil
    }
    
    // 4. Парсинг валюты
    /// The currency the text names, if any. "$" and "dollars" read in the local
    /// currency when it is a dollar (a Canadian says "12 dollars" for CAD):
    /// the named account's currency, else the default account's.
    private func parseCurrency(from text: String, accountId: String?) -> String? {
        let localCurrency = accountId.flatMap { id in liveAccounts.first { $0.id == id }?.currency }
            ?? cachedDefaultAccount?.currency
            ?? liveAccounts.first { !$0.isLoan && !$0.isDeposit }?.currency
        return Self.currencyCode(in: text, localCurrency: localCurrency)
    }

    /// Currency words and signs, longest first so "r$" wins over "$" and the
    /// result doesn't depend on `Dictionary` order. "$" and "dollar" are
    /// placeholders that `currencyCode(in:localCurrency:)` resolves.
    /// "tl" is intentionally absent: it is a substring of common Turkish words
    /// ("katlı", "atlet"); "lira"/"₺" are unambiguous.
    private static let currencyKeywords: [(keyword: String, code: String)] = [
        ("тенге", "KZT"), ("теңге", "KZT"), ("тг", "KZT"), ("₸", "KZT"),
        ("доллар", "dollar"), ("долларов", "dollar"), ("dollar", "dollar"), ("dólar", "dollar"), ("dolar", "dollar"),
        ("usd", "USD"), ("$", "$"),
        ("евро", "EUR"), ("еуро", "EUR"), ("eur", "EUR"), ("€", "EUR"),
        ("рубл", "RUB"), ("rub", "RUB"), ("₽", "RUB"),
        ("lira", "TRY"), ("₺", "TRY"),
        ("reais", "BRL"), ("r$", "BRL"),
        ("гривень", "UAH"), ("гривня", "UAH"), ("гривні", "UAH"), ("грн", "UAH"), ("₴", "UAH"),
        ("円", "JPY"), ("¥", "JPY"),
        ("원", "KRW"), ("₩", "KRW")
    ].sorted { $0.keyword.count != $1.keyword.count ? $0.keyword.count > $1.keyword.count : $0.keyword < $1.keyword }

    /// Currencies written with a bare "$" at home.
    private static let dollarSignCurrencies: Set<String> = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "TWD", "MXN", "ARS", "CLP", "COP"]

    /// Currencies called "dollars" at home.
    private static let dollarNamedCurrencies: Set<String> = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "TWD"]

    /// The currency `text` names. A keyword that starts with a letter only
    /// counts at the start of a word, so "eur" doesn't fire inside "coiffeur"
    /// or "원" inside "병원"; signs count anywhere.
    static func currencyCode(in text: String, localCurrency: String?) -> String? {
        for (keyword, code) in currencyKeywords where containsCurrencyKeyword(keyword, in: text) {
            switch code {
            case "$":
                return localCurrency.flatMap { dollarSignCurrencies.contains($0) ? $0 : nil } ?? "USD"
            case "dollar":
                return localCurrency.flatMap { dollarNamedCurrencies.contains($0) ? $0 : nil } ?? "USD"
            default:
                return code
            }
        }
        return nil
    }

    private static func containsCurrencyKeyword(_ keyword: String, in text: String) -> Bool {
        guard keyword.first?.isLetter == true else { return text.contains(keyword) }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: keyword, range: searchStart..<text.endIndex) {
            if range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter {
                return true
            }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    // Результат поиска счета
    private struct AccountSearchResult {
        let accountId: String?
        let reason: String
    }
    
    // 5. Поиск счета по тексту (с токенизацией и скорингом)
    private func findAccount(from text: String) -> AccountSearchResult {
        var accountName: String?

        // Используем pre-compiled regex для производительности
        for regex in accountPatternRegexes {
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                accountName = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // Токенизация текста (убираем стоп-слова)
        let textTokens = tokenize(text)
        
        // Скоринг счетов
        var accountScores: [(Account, Int, String)] = [] // (account, score, reason)

        for account in liveAccounts {
            let normalizedAccountName = normalizeText(account.name)
            let accountTokens = tokenize(normalizedAccountName)
            
            var score = 0
            var reason = ""
            
            // Проверяем алиасы
            for (key, aliases) in accountAliases {
                if normalizedAccountName.contains(key) {
                    for alias in aliases {
                        if text.contains(alias) {
                            score += VoiceInputConstants.accountAliasMatchScore
                            reason = "Найден по алиасу '\(alias)'"
                            break
                        }
                    }
                }
            }

            // Точное совпадение имени
            if text.contains(normalizedAccountName) {
                score += VoiceInputConstants.accountExactMatchScore
                if reason.isEmpty {
                    reason = "Точное совпадение имени"
                }
            }

            // Совпадение токенов
            let matchingTokens = accountTokens.filter { token in
                textTokens.contains(token) && !stopWords.contains(token)
            }
            if !matchingTokens.isEmpty {
                score += matchingTokens.count * VoiceInputConstants.accountTokenMatchScore
                if reason.isEmpty {
                    reason = "Совпадение токенов: \(matchingTokens.joined(separator: ", "))"
                }
            }

            // Если нашли по паттерну
            if let accountName = accountName, normalizedAccountName.contains(normalizeText(accountName)) {
                score += VoiceInputConstants.accountPatternMatchScore
                reason = "Найден по паттерну: '\(accountName)'"
            }
            
            if score > 0 {
                accountScores.append((account, score, reason))
            }
        }
        
        // Сортируем по скору
        accountScores.sort { $0.1 > $1.1 }
        
        // Если есть несколько кандидатов с близким скором, возвращаем nil для выбора на confirm
        if accountScores.count >= 2 {
            let bestScore = accountScores[0].1
            let secondScore = accountScores[1].1
            if bestScore - secondScore < VoiceInputConstants.accountScoreAmbiguityThreshold {
                return AccountSearchResult(
                    accountId: nil,
                    reason: "Несколько кандидатов с близким скором: \(accountScores[0].0.name) (\(bestScore)) vs \(accountScores[1].0.name) (\(secondScore))"
                )
            }
        }
        
        if let bestMatch = accountScores.first {
            return AccountSearchResult(accountId: bestMatch.0.id, reason: bestMatch.2)
        }
        
        return AccountSearchResult(accountId: nil, reason: "Счет не найден")
    }
    
    // Токенизация текста (удаление стоп-слов)
    private func tokenize(_ text: String) -> [String] {
        return text.components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }
    
    /// Suggestion-only lookup into the keyword maps for imported merchant strings.
    /// Unlike `parseCategory`, it never falls back to "Other" and matches whole
    /// words (`CategorySuggestionService.matches`), so "medicine" does not hit
    /// "cine". Returns the user's category from the target's preset group
    /// (`resolveCategoryName`), else the map's raw name (e.g. "Транспорт"); the
    /// caller resolves it against the user's categories.
    func keywordCategory(in text: String) -> String? {
        let merchant = CategorySuggestionService.normalizedMerchant(text)
        guard !merchant.isEmpty else { return nil }
        for keyword in sortedCategoryKeys
        where CategorySuggestionService.matches(keyword: keyword.key, inNormalized: merchant) {
            if let entry = categoryEntry(keyword) { return resolveCategoryName(entry.category) }
        }
        return nil
    }

    /// Every category name the keyword map can produce. `VoiceCategoryTargetsTests`
    /// pins these to real onboarding preset names, so a map value can never again
    /// point at a category nobody has (the old "Еда"/"Покупки" targets sent the most
    /// common Russian phrases to "Other").
    var categoryMapTargets: Set<String> {
        Set(categoryMap.values.map(\.category)).union(wholeWordCategoryMap.values.map(\.category))
    }

    // 6. Парсинг категории и подкатегорий (сначала подкатегории, потом категории)
    private func parseCategory(from text: String) -> (category: String?, subcategories: [String], isGuess: Bool) {
        // Сначала ищем подкатегории, потом категории
        var foundSubcategories: [String] = []
        var foundCategory: String?

        // Longest keyword first, in a total order (`sortedCategoryKeys`).
        for keyword in sortedCategoryKeys {
            guard let (category, subcategory) = categoryEntry(keyword) else { continue }
            if matches(keyword, in: text) {
                // Сначала проверяем подкатегорию
                if let subcategory = subcategory {
                    let matchingSubcategory = liveSubcategories.first { normalizeText($0.name) == normalizeText(subcategory) }
                    if let matchingSubcategory = matchingSubcategory {
                        foundSubcategories.append(matchingSubcategory.name)
                    }
                }
                
                // Затем категорию: своя у пользователя, в том числе под именем
                // из другого языка ("groceries" → "Продукты")
                if foundCategory == nil {
                    foundCategory = resolveCategoryName(category)
                }
                
                // Если нашли и подкатегорию и категорию, можно выйти
                if !foundSubcategories.isEmpty && foundCategory != nil {
                    break
                }
            }
        }
        
        // Если не нашли, возвращаем "Другое": "category.other" ("Другое") или
        // пресет "Прочее" на любом языке
        let isGuess = foundCategory == nil
        if foundCategory == nil {
            let otherName = String(localized: "category.other")
            foundCategory = liveCategoryName(otherName)
                ?? Self.categoryGroupByName[Self.categoryNameKey("Other")]?.lazy.compactMap { self.liveCategoryName($0) }.first
                ?? otherName
        }
        
        return (foundCategory, foundSubcategories, isGuess)
    }

    // MARK: - Live Entity Recognition

    /// Parse entities from text in real-time for UI highlighting
    /// - Parameter text: Text to parse
    /// - Returns: Array of recognized entities with positions and confidence
    func parseEntitiesLive(from text: String) -> [RecognizedEntity] {
        var entities: [RecognizedEntity] = []
        let nsText = text as NSString

        // 1. Detect amounts. Multi-clause input ("500 такси и 1000 продукты")
        //    has multiple amounts — we want every one of them highlighted.
        entities.append(contentsOf: detectAmountEntities(in: text, nsText: nsText))

        // 2. Detect Currency
        if let currencyEntity = detectCurrencyEntity(in: text, nsText: nsText) {
            entities.append(currencyEntity)
        }

        // 3. Detect Category
        if let categoryEntity = detectCategoryEntity(in: text, nsText: nsText) {
            entities.append(categoryEntity)
        }

        // 4. Detect Account
        if let accountEntity = detectAccountEntity(in: text, nsText: nsText) {
            entities.append(accountEntity)
        }

        // 5. Detect Transaction Type (income/expense keywords)
        if let typeEntity = detectTransactionTypeEntity(in: text, nsText: nsText) {
            entities.append(typeEntity)
        }

        return entities
    }

    // MARK: - Entity Detection Methods

    private func detectAmountEntities(in text: String, nsText: NSString) -> [RecognizedEntity] {
        // First two regex patterns capture amounts WITH a currency token;
        // they're high-confidence so we surface every match.
        var entities: [RecognizedEntity] = []
        var consumedRanges: [NSRange] = []
        let fullRange = NSRange(location: 0, length: nsText.length)

        for regex in amountRegexes.prefix(2) {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                // Avoid double-counting when two regexes overlap on the same span.
                if consumedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                let matchedText = nsText.substring(with: match.range)
                let lowered = matchedText.lowercased()
                let hasCurrency = lowered.contains("тенге") || lowered.contains("тг") || matchedText.contains("₸")
                entities.append(RecognizedEntity(
                    type: .amount,
                    range: match.range,
                    value: matchedText,
                    confidence: hasCurrency ? 0.9 : 0.7
                ))
                consumedRanges.append(match.range)
            }
        }

        return entities
    }

    private func detectCurrencyEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        let currencyPattern = #"(тенге|тг|₸|доллар|евро|рубл)"#
        guard let regex = try? NSRegularExpression(pattern: currencyPattern, options: .caseInsensitive) else {
            return nil
        }

        if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
            return RecognizedEntity(
                type: .currency,
                range: match.range,
                value: nsText.substring(with: match.range),
                confidence: 0.95
            )
        }

        return nil
    }

    private func detectCategoryEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        let normalizedText = normalizeText(text)

        // Same keywords and order as `parseCategory`
        for keyword in sortedCategoryKeys where matches(keyword, in: normalizedText) {
            guard let categoryInfo = categoryEntry(keyword) else { continue }
            // Find position of keyword
            if let range = text.lowercased().range(of: keyword.key) {
                let nsRange = NSRange(range, in: text)
                return RecognizedEntity(
                    type: .category,
                    range: nsRange,
                    value: categoryInfo.category,
                    confidence: 0.8
                )
            }
        }

        return nil
    }

    private func detectAccountEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        // Try account patterns
        for regex in accountPatternRegexes {
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let matchedText = nsText.substring(with: match.range)
                return RecognizedEntity(
                    type: .account,
                    range: match.range,
                    value: matchedText,
                    confidence: 0.75
                )
            }
        }

        return nil
    }

    private func detectTransactionTypeEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        let normalizedText = normalizeText(text)

        // Check for income keywords
        for keyword in incomeKeywords {
            if normalizedText.contains(keyword) {
                if let range = text.lowercased().range(of: keyword) {
                    let nsRange = NSRange(range, in: text)
                    return RecognizedEntity(
                        type: .transactionType,
                        range: nsRange,
                        value: "income",
                        confidence: 0.85
                    )
                }
            }
        }

        // Check for expense keywords
        for keyword in expenseKeywords {
            if normalizedText.contains(keyword) {
                if let range = text.lowercased().range(of: keyword) {
                    let nsRange = NSRange(range, in: text)
                    return RecognizedEntity(
                        type: .transactionType,
                        range: nsRange,
                        value: "expense",
                        confidence: 0.85
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Smart Default Account Selection

    /// Get smart default account based on usage statistics.
    /// - Parameter category: Optional category to bias the lookup toward
    ///   accounts most-used for transactions in that category.
    private func getSmartDefaultAccount(forCategory category: String? = nil) -> Account? {
        guard !liveAccounts.isEmpty else { return nil }
        guard !liveTransactions.isEmpty else { return liveAccounts.first }

        let tracker = AccountUsageTracker(transactions: liveTransactions, accounts: liveAccounts)
        let preferred = tracker.getSmartDefaultAccount(forCategory: category)

        // Filter out loan/deposit accounts — voice quick-save targets only
        // regular accounts.
        if let preferred, !preferred.isLoan, !preferred.isDeposit {
            return preferred
        }
        return liveAccounts.first(where: { !$0.isLoan && !$0.isDeposit })
            ?? liveAccounts.first
    }

    /// Resolve the best-guess account for a clause whose category is `category`.
    /// Composes user-learned preferences (highest priority) with usage stats
    /// (fallback). Result is cached per-category for the current parse.
    private func smartDefaultAccount(forCategory category: String?) -> Account? {
        let cacheKey = category?.lowercased() ?? ""
        if let cached = cachedDefaultsByCategory[cacheKey] {
            return cached
        }

        // 1. User's learned preference, if confident and the account is
        //    still a regular (non-loan / non-deposit) account.
        if let preferredId = learningStore.preferredAccountID(forCategory: category, where: { id in
            liveAccounts.contains(where: { $0.id == id && !$0.isLoan && !$0.isDeposit })
        }),
        let preferred = liveAccounts.first(where: { $0.id == preferredId }) {
            cachedDefaultsByCategory[cacheKey] = preferred
            return preferred
        }

        // 2. Usage-based per-category default.
        if let usageBased = getSmartDefaultAccount(forCategory: category) {
            cachedDefaultsByCategory[cacheKey] = usageBased
            return usageBased
        }
        return nil
    }
}
