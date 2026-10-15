//
//  ScreenshotDemoLexicon+Ten.swift
//  Tenra
//
//  DEBUG-only: the words of the 1.6 screenshots per UI language. Ten's answer to "My spending
//  this month" (ScreenshotDemoTransport: its figures come from the tools, only the words are
//  here), and the names in the seeded savings goals, personal debts and remembered fact
//  (ScreenshotDemoSeeder). Like the rest of the lexicon these are user data or model output in
//  production, so they never touch Localizable.strings. No em dashes (user rule).
//

import Foundation

#if DEBUG

extension ScreenshotDemoLexicon {

    struct Ten {
        /// The answer's first text block (Markdown, the main thought in bold).
        let answerIntro: String
        /// The metric card: this month's spending.
        let answerMetric: String
        /// The breakdown card: this month by category.
        let answerChart: String
        /// The answer's last text block.
        let answerTip: String
        /// A goal without an account, with money added by hand and a deadline.
        let goalManual: String
        /// A goal that follows the savings account.
        let goalLinked: String
        /// A goal already reached.
        let goalReached: String
        /// Someone who owes the person money, past the due date.
        let lentPerson: String
        let lentNote: String
        /// Someone the person owes, due in a couple of weeks.
        let borrowedPerson: String
        /// What Ten remembers (Settings › Assistant).
        let fact: String
    }

    /// The UI language as the lexicon tells them apart: "es-MX" and "fr-CA" have their own words.
    static var languageKey: String {
        let preferred = (Locale.preferredLanguages.first ?? "en").lowercased()
        if preferred.hasPrefix("es-mx") { return "es-MX" }
        if preferred.hasPrefix("fr-ca") { return "fr-CA" }
        return String(preferred.prefix(2))
    }

    static func ten() -> Ten {
        switch languageKey {
        case "de":
            return Ten(
                answerIntro: "**Hier ist Ihr Monat bisher.** Die Summe steht neben denselben Tagen im Vormonat, darunter sehen Sie, wohin das Geld ging.",
                answerMetric: "Ausgaben diesen Monat",
                answerChart: "Nach Kategorie",
                answerTip: "Lebensmittel und Essengehen schwanken von Woche zu Woche am stärksten: Dort bringen kleine Einsparungen am meisten.",
                goalManual: "Neuer Laptop", goalLinked: "Urlaub", goalReached: "Kopfhörer",
                lentPerson: "Jonas", lentNote: "Konzertkarten", borrowedPerson: "Lena",
                fact: "Das Gehalt kommt am 5. des Monats"
            )
        case "es-MX":
            return Ten(
                answerIntro: "**Así va tu mes.** El total junto a los mismos días del mes pasado y, abajo, a dónde se fue el dinero.",
                answerMetric: "Gastado este mes",
                answerChart: "Por categoría",
                answerTip: "El súper y comer fuera son lo que más cambia de una semana a otra: ahí es donde los pequeños recortes se notan.",
                goalManual: "Laptop nueva", goalLinked: "Vacaciones", goalReached: "Audífonos",
                lentPerson: "Diego", lentNote: "Boletos del concierto", borrowedPerson: "Sofía",
                fact: "El sueldo llega el día 5"
            )
        case "es":
            return Ten(
                answerIntro: "**Así va tu mes.** El total junto a los mismos días del mes pasado y, debajo, a dónde se fue el dinero.",
                answerMetric: "Gastado este mes",
                answerChart: "Por categoría",
                answerTip: "La compra y comer fuera son lo que más cambia de una semana a otra: ahí es donde los pequeños recortes se notan.",
                goalManual: "Portátil nuevo", goalLinked: "Vacaciones", goalReached: "Auriculares",
                lentPerson: "Carlos", lentNote: "Entradas del concierto", borrowedPerson: "Lucía",
                fact: "La nómina llega el día 5"
            )
        case "fr-CA":
            return Ten(
                answerIntro: "**Voici votre mois jusqu'ici.** Le total à côté des mêmes jours du mois dernier, et en dessous, où est parti l'argent.",
                answerMetric: "Dépensé ce mois-ci",
                answerChart: "Par catégorie",
                answerTip: "L'épicerie et les sorties au restaurant varient le plus d'une semaine à l'autre : c'est là que les petites économies comptent.",
                goalManual: "Nouvel ordinateur", goalLinked: "Vacances", goalReached: "Écouteurs",
                lentPerson: "Mathieu", lentNote: "Billets de spectacle", borrowedPerson: "Émilie",
                fact: "La paie arrive le 5 du mois"
            )
        case "fr":
            return Ten(
                answerIntro: "**Voici votre mois jusqu'ici.** Le total à côté des mêmes jours du mois dernier, et en dessous, où est parti l'argent.",
                answerMetric: "Dépensé ce mois-ci",
                answerChart: "Par catégorie",
                answerTip: "Les courses et les sorties au restaurant varient le plus d'une semaine à l'autre : c'est là que les petites économies comptent.",
                goalManual: "Nouvel ordinateur", goalLinked: "Vacances", goalReached: "Casque audio",
                lentPerson: "Julien", lentNote: "Billets de concert", borrowedPerson: "Claire",
                fact: "Le salaire arrive le 5 du mois"
            )
        case "tr":
            return Ten(
                answerIntro: "**İşte bu ay şu ana kadar.** Toplam, geçen ayın aynı günlerinin yanında; altında da paranın nereye gittiği var.",
                answerMetric: "Bu ay harcanan",
                answerChart: "Kategoriye göre",
                answerTip: "Haftadan haftaya en çok market ve dışarıda yemek değişiyor: küçük kesintiler en çok orada fark eder.",
                goalManual: "Yeni dizüstü", goalLinked: "Tatil", goalReached: "Kulaklık",
                lentPerson: "Emre", lentNote: "Konser biletleri", borrowedPerson: "Ayşe",
                fact: "Maaş her ayın 5'inde yatıyor"
            )
        case "pt":
            return Ten(
                answerIntro: "**Este é o seu mês até agora.** O total ao lado dos mesmos dias do mês passado e, abaixo, para onde foi o dinheiro.",
                answerMetric: "Gasto este mês",
                answerChart: "Por categoria",
                answerTip: "Mercado e comer fora são o que mais muda de uma semana para outra: é aí que pequenos cortes fazem diferença.",
                goalManual: "Notebook novo", goalLinked: "Viagem", goalReached: "Fones de ouvido",
                lentPerson: "João", lentNote: "Ingressos do show", borrowedPerson: "Ana",
                fact: "O salário cai no dia 5"
            )
        case "it":
            return Ten(
                answerIntro: "**Ecco il tuo mese finora.** Il totale accanto agli stessi giorni del mese scorso e, sotto, dove sono andati i soldi.",
                answerMetric: "Speso questo mese",
                answerChart: "Per categoria",
                answerTip: "Spesa e pasti fuori sono ciò che cambia di più da una settimana all'altra: è lì che i piccoli tagli si sentono.",
                goalManual: "Portatile nuovo", goalLinked: "Vacanze", goalReached: "Cuffie",
                lentPerson: "Marco", lentNote: "Biglietti del concerto", borrowedPerson: "Giulia",
                fact: "Lo stipendio arriva il 5 del mese"
            )
        case "uk":
            return Ten(
                answerIntro: "**Ось ваш місяць на сьогодні.** Підсумок поруч із тими самими днями минулого місяця, а нижче, куди пішли гроші.",
                answerMetric: "Витрачено цього місяця",
                answerChart: "За категоріями",
                answerTip: "Найбільше від тижня до тижня змінюються продукти й кафе, тож невелика економія там найпомітніша.",
                goalManual: "Новий ноутбук", goalLinked: "Відпустка", goalReached: "Навушники",
                lentPerson: "Олег", lentNote: "Квитки на концерт", borrowedPerson: "Ірина",
                fact: "Зарплата приходить 5-го числа"
            )
        case "ja":
            return Ten(
                answerIntro: "**今月のここまでの支出です。** 先月の同じ期間と比べた合計と、その内訳をまとめました。",
                answerMetric: "今月の支出",
                answerChart: "カテゴリ別",
                answerTip: "週ごとの変動がいちばん大きいのは食料品と外食です。少しの節約が効きやすいのもここです。",
                goalManual: "新しいノートPC", goalLinked: "旅行", goalReached: "ヘッドホン",
                lentPerson: "佐藤さん", lentNote: "コンサートのチケット", borrowedPerson: "田中さん",
                fact: "給料日は毎月5日"
            )
        case "ko":
            return Ten(
                answerIntro: "**이번 달 지금까지의 지출이에요.** 지난달 같은 기간과 비교한 합계와 어디에 썼는지 정리했어요.",
                answerMetric: "이번 달 지출",
                answerChart: "카테고리별",
                answerTip: "주마다 가장 크게 달라지는 건 장보기와 외식이에요. 작은 절약도 여기서 가장 티가 나요.",
                goalManual: "새 노트북", goalLinked: "여행", goalReached: "헤드폰",
                lentPerson: "민준", lentNote: "콘서트 티켓", borrowedPerson: "지은",
                fact: "월급은 매달 5일에 들어와요"
            )
        case "ru":
            return Ten(
                answerIntro: "**Вот ваш месяц на сегодня.** Итог рядом с теми же днями прошлого месяца, а ниже, куда ушли деньги.",
                answerMetric: "Потрачено в этом месяце",
                answerChart: "По категориям",
                answerTip: "Сильнее всего от недели к неделе меняются продукты и кафе, поэтому небольшая экономия там заметнее всего.",
                goalManual: "Новый ноутбук", goalLinked: "Отпуск", goalReached: "Наушники",
                lentPerson: "Артём", lentNote: "Билеты на концерт", borrowedPerson: "Аня",
                fact: "Зарплата приходит 5-го числа"
            )
        default:
            return Ten(
                answerIntro: "**Here's your month so far.** The total sits next to the same days of last month, and below is where it went.",
                answerMetric: "Spent this month",
                answerChart: "By category",
                answerTip: "Groceries and eating out change the most from week to week, so that's where small cuts add up.",
                goalManual: "New laptop", goalLinked: "Vacation", goalReached: "Headphones",
                lentPerson: "Alex", lentNote: "Concert tickets", borrowedPerson: "Sam",
                fact: "Salary comes on the 5th"
            )
        }
    }
}

#endif
