//
//  CategoryIcon.swift
//  AIFinanceManager
//
//  Utility for getting SF Symbol icon names for categories
//

import Foundation

enum CategoryIcon {
    static func iconName(for category: String, type: TransactionType, customCategories: [CustomCategory] = []) -> String {
        // Для операций перевода всегда возвращаем arrow.left.arrow.right
        if type == .internalTransfer {
            return "arrow.left.arrow.right"
        }
        
        // Сначала проверяем пользовательские категории
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() && $0.type == type }) {
            if case .sfSymbol(let symbolName) = custom.iconSource {
                return symbolName
            }
        }
        
        // Затем дефолтные (поддержка английских и русских названий)
        let key = category.lowercased()
        let map: [String: String] = [
            // Английские
            "income": "dollarsign.circle.fill",
            "food": "fork.knife",
            "transport": "car.fill",
            "shopping": "bag.fill",
            "entertainment": "sparkles",
            "bills": "lightbulb.fill",
            "health": "cross.case.fill",
            "education": "graduationcap.fill",
            "other": "banknote.fill",
            "salary": "briefcase.fill",
            "delivery": "box.fill",
            "gifts": "gift.fill",
            "travel": "airplane",
            "groceries": "cart.fill",
            "coffee": "cup.and.saucer.fill",
            "subscriptions": "tv.fill",
            "transfer": "arrow.left.arrow.right",
            // Русские
            "доход": "dollarsign.circle.fill",
            "доходы": "dollarsign.circle.fill",
            "еда": "fork.knife",
            "продукты": "cart.fill",
            "транспорт": "car.fill",
            "покупки": "bag.fill",
            "развлечения": "sparkles",
            "счета": "lightbulb.fill",
            "здоровье": "cross.case.fill",
            "образование": "graduationcap.fill",
            "другое": "banknote.fill",
            "зарплата": "briefcase.fill",
            "доставка": "box.fill",
            "подарки": "gift.fill",
            "путешествия": "airplane",
            "кофе": "cup.and.saucer.fill",
            "подписки": "tv.fill",
            "перевод": "arrow.left.arrow.right",
            "такси": "car.fill",
            "автобус": "bus.fill",
            "метро": "tram.fill",
            "ресторан": "fork.knife",
            "кафе": "cup.and.saucer.fill",
            "обед": "fork.knife",
            "ужин": "fork.knife",
            "магазин": "cart.fill",
            "супермаркет": "cart.fill",
            "аптека": "pills.fill",
            "больница": "cross.case.fill",
            "врач": "cross.case.fill",
            "лечение": "cross.case.fill",
            "школа": "graduationcap.fill",
            "университет": "graduationcap.fill",
            "курсы": "graduationcap.fill",
            "кино": "film.fill",
            "театр": "theatermasks.fill",
            "концерт": "music.note",
            "спорт": "sportscourt.fill",
            "фитнес": "dumbbell.fill",
            "одежда": "tshirt.fill",
            "обувь": "shoe.2.fill",
            "техника": "iphone",
            "компьютер": "laptopcomputer",
            "телефон": "iphone",
            "интернет": "globe",
            "связь": "phone.fill",
            "коммунальные": "lightbulb.fill",
            "электричество": "bolt.fill",
            "газ": "flame.fill",
            "вода": "drop.fill",
            "квартплата": "house.fill",
            "аренда": "house.fill",
            "ипотека": "building.columns.fill",
            "кредит": "creditcard.fill",
            "страховка": "shield.fill",
            "налоги": "chart.bar.fill",
            "пенсия": "person.fill",
            "пособие": "dollarsign.circle.fill",
            "дивиденды": "chart.line.uptrend.xyaxis",
            "инвестиции": "chart.bar.fill",
            "бизнес": "briefcase.fill",
            "услуги": "wrench.and.screwdriver.fill",
            "ремонт": "hammer.fill",
            "красота": "paintbrush.fill",
            "парикмахер": "scissors",
            "салон": "paintbrush.fill",
            "книги": "book.fill",
            "игры": "gamecontroller.fill",
            "музыка": "music.note",
            "стриминг": "tv.fill",
            "подписка": "tv.fill",
            "бензин": "fuelpump.fill",
            "парковка": "parking.circle.fill",
            "мойка": "shower.fill",
            "ремонт авто": "wrench.and.screwdriver.fill",
            "страховка авто": "car.fill",
            "проезд": "bus.fill",
            "билет": "ticket.fill",
            "отель": "building.2",
            "отпуск": "airplane",
            "туризм": "map.fill",
            "виза": "key.fill",
            "багаж": "suitcase.fill"
        ]
        
        // Проверяем точное совпадение
        if let value = map[key] { return value }
        
        // Проверяем частичное совпадение (если название содержит ключевое слово)
        for (keyword, iconName) in map {
            if key.contains(keyword) || keyword.contains(key) {
                return iconName
            }
        }
        
        return type == .income ? "dollarsign.circle.fill" : "banknote.fill"
    }
}
