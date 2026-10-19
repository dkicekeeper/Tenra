//
//  ScreenshotDemoTransport.swift
//  Tenra
//
//  DEBUG-only: Ten's server during screenshot capture. The Simulator has no App Attest and the
//  capture has no network, so each of the demo's questions (its presets, in this order) gets
//  what the model does for it: one tool, which the real FinanceToolkit answers on the phone from
//  the seeded data, then a reply on cards over that result with the lexicon's words.
//    - "My spending this month": the spending summary, its total and a donut of categories.
//    - "What do my subscriptions cost?": the subscriptions, their monthly total and the list.
//    - All currencies: the accounts, their total in the base currency and the foreign account.
//    - An early loan payment: the loan simulator, interest saved and months sooner.
//  The events come with short pauses, so the chat shows Ten thinking as it does with the server.
//

import Foundation

#if DEBUG

nonisolated final class ScreenshotDemoTransport: AgentTransport, @unchecked Sendable {
    private let reply: ScreenshotDemoReply

    init(reply: ScreenshotDemoReply) {
        self.reply = reply
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let events = Self.events(for: messages, reply: reply)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    try? await Task.sleep(for: .milliseconds(400))
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A message with a question (a text block) gets the topic's tool call; one with only tool
    /// results gets the reply over the result it carries.
    static func events(for messages: [AgentWireMessage], reply: ScreenshotDemoReply) -> [AgentStreamEvent] {
        guard let last = messages.last else { return [] }
        let callId = "demo_\(messages.count)"
        let topic = reply.topic(asked: question(in: messages))
        if last.content.contains(where: { $0["type"] == "text" }) {
            let (name, input) = reply.call(for: topic)
            return [.tool(name: name), done([use(id: callId, name: name, input: input)])]
        }
        let result = last.content.lazy.compactMap(toolResult(of:)).first
        let source = result?[AgentProtocol.resultIdKey]?.stringValue ?? "r1"
        let render = use(id: callId, name: AgentProtocol.renderReplyTool, input: reply.render(topic, source: source, result: result))
        return [.tool(name: AgentProtocol.renderReplyTool), done([render])]
    }

    /// The person's words: the last text block of the latest message with text (the phone puts
    /// its context and notes before them).
    private static func question(in messages: [AgentWireMessage]) -> String {
        let asked = messages.last(where: { message in message.role == .user && message.content.contains { $0["type"] == "text" } })
        return asked?.content.last(where: { $0["type"] == "text" })?["text"]?.stringValue ?? ""
    }

    private static func use(id: String, name: String, input: JSONValue) -> JSONValue {
        ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]
    }

    private static func done(_ content: [JSONValue]) -> AgentStreamEvent {
        .done(AgentTurnDone(
            content: content,
            stopReason: "tool_use",
            model: "screenshot-demo",
            refused: false,
            truncated: false,
            usage: AgentUsage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0),
            tier: "pro",
            quota: nil
        ))
    }

    /// A tool result as the phone sent it, with the `result_id` it put in (AgentConversation
    /// names them r1, r2…).
    private static func toolResult(of block: JSONValue) -> JSONValue? {
        guard block["type"] == "tool_result", case .string(let content)? = block["content"],
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(content.utf8)),
              value[AgentProtocol.resultIdKey]?.stringValue != nil else { return nil }
        return value
    }
}

/// What the scripted Ten says, in the app's language: the replies' sentences and the questions
/// the app has no preset for from the demo lexicon, the card titles and suggestions from the
/// app's own strings where it has them.
nonisolated struct ScreenshotDemoReply: Sendable {
    enum Topic: Sendable {
        case month, subscriptions, currencies, loan
    }

    let text: String
    let metricLabel: String
    let chartTitle: String
    let suggestions: [String]
    /// This month so far, as the spending tool takes it.
    let from: String
    let to: String

    let subscriptionsQuestion: String
    let subscriptionsText: String
    let subscriptionsLabel: String

    let currenciesQuestion: String
    let currenciesText: String
    let currenciesTotalLabel: String
    /// The foreign-currency savings account, its card titled with its name.
    let savingsLabel: String

    let loanQuestion: String
    let loanText: String
    let loanOneOff: Double
    let loanInterestLabel: String
    let loanMonthsLabel: String

    /// The seeder's account ids (ScreenshotDemoSeeder).
    static let savingsAccountId = "demo-account-savings"
    static let loanAccountId = "demo-account-loan"

    /// The demo's presets on Ten's tab, in the order the capture taps them.
    var questions: [String] {
        [chartTitle, subscriptionsQuestion, currenciesQuestion, loanQuestion]
    }

    func topic(asked question: String) -> Topic {
        switch question {
        case subscriptionsQuestion: .subscriptions
        case currenciesQuestion: .currencies
        case loanQuestion: .loan
        default: .month
        }
    }

    /// The tool the model calls for the question.
    func call(for topic: Topic) -> (name: String, input: JSONValue) {
        switch topic {
        case .month:
            ("get_spending_summary", ["from": .string(from), "to": .string(to), "type": "expense", "group_by": "category"])
        case .subscriptions:
            ("list_recurring", ["kind": "subscription", "active_only": true])
        case .currencies:
            ("get_accounts", [:])
        case .loan:
            ("simulate_loan", ["account_id": .string(Self.loanAccountId), "one_off": .number(loanOneOff)])
        }
    }

    /// `render_reply`'s input over the tool's result.
    func render(_ topic: Topic, source: String, result: JSONValue?) -> JSONValue {
        let blocks: [JSONValue]
        var mood = "happy"
        switch topic {
        case .month:
            blocks = [
                ["type": "text", "text": .string(text)],
                ["type": "metric", "label": .string(metricLabel), "source": .string(source), "path": "total"],
                ["type": "chart", "kind": "donut", "title": .string(chartTitle), "source": .string(source), "path": "groups"],
            ]
        case .subscriptions:
            blocks = [
                ["type": "text", "text": .string(subscriptionsText)],
                ["type": "metric", "label": .string(subscriptionsLabel), "source": .string(source), "path": "subscriptions_monthly_total_base"],
                ["type": "recurring", "source": .string(source)],
            ]
        case .currencies:
            let savings = result?["accounts"]?.arrayValue?.firstIndex(where: { $0["id"] == .string(Self.savingsAccountId) }) ?? 0
            blocks = [
                ["type": "text", "text": .string(currenciesText)],
                ["type": "metric", "label": .string(currenciesTotalLabel), "source": .string(source), "path": "total_base"],
                ["type": "metric", "label": .string(savingsLabel), "source": .string(source), "path": .string("accounts.\(savings).balance")],
            ]
        case .loan:
            mood = "proud"
            blocks = [
                ["type": "text", "text": .string(loanText)],
                ["type": "metric", "label": .string(loanInterestLabel), "source": .string(source), "path": "interest_saved"],
                ["type": "metric", "label": .string(loanMonthsLabel), "source": .string(source), "path": "months_saved"],
            ]
        }
        return [
            "blocks": .array(blocks),
            "mood": .string(mood),
            "suggestions": .array(suggestions.map(JSONValue.string)),
        ]
    }

    @MainActor
    static func current(now: Date = Date(), calendar: Calendar = .current) -> ScreenshotDemoReply {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let lexicon = ScreenshotDemoLexicon.current()
        let lines = ScreenshotDemoTenLines.current()
        let currency = ScreenshotDemoMode.currencyCode
        // The seeder's savings account is in dollars, or in euros where dollars are the base.
        let savingsCurrency = currency == "USD" ? "EUR" : "USD"
        let oneOff = ScreenshotDemoCurrency.amount(1000, in: currency)
        return ScreenshotDemoReply(
            text: lexicon.tenReply,
            metricLabel: String(localized: "insights.expenses"),
            chartTitle: String(localized: "assistant.preset.month"),
            suggestions: [String(localized: "assistant.preset.compare"), String(localized: "assistant.preset.budgets")],
            from: FastDateParser.string(from: start),
            to: FastDateParser.string(from: now),
            subscriptionsQuestion: String(localized: "assistant.preset.subscriptions"),
            subscriptionsText: lines.subscriptionsReply,
            subscriptionsLabel: lines.perMonth,
            currenciesQuestion: lines.currenciesQuestion,
            currenciesText: lines.currenciesReply,
            currenciesTotalLabel: lines.total,
            savingsLabel: lexicon.savings.replacingOccurrences(of: "USD", with: savingsCurrency),
            loanQuestion: String(format: lines.loanQuestion, Formatting.formatCurrencySmart(oneOff, currency: currency)),
            loanText: lines.loanReply,
            loanOneOff: oneOff,
            loanInterestLabel: lines.interestSaved,
            loanMonthsLabel: lines.monthsSooner
        )
    }
}

/// The demo lexicon's lines for Ten's topical answers (ScreenshotDemoReply): the questions the
/// app has no preset for, the replies' sentences and the cards' titles. The loan question takes
/// the formatted amount for its `%@`.
nonisolated struct ScreenshotDemoTenLines: Sendable {
    let perMonth: String
    let total: String
    let subscriptionsReply: String
    let currenciesQuestion: String
    let currenciesReply: String
    let loanQuestion: String
    let loanReply: String
    let interestSaved: String
    let monthsSooner: String

    static func current() -> ScreenshotDemoTenLines {
        let language = String((Locale.preferredLanguages.first ?? "en").prefix(2)).lowercased()
        switch language {
        case "de":
            return .init(perMonth: "Pro Monat", total: "Gesamt",
                         subscriptionsReply: "Hier sind alle Ihre Abos und was sie im Monat kosten.",
                         currenciesQuestion: "Wie viel Geld habe ich in allen Währungen?",
                         currenciesReply: "Alle Ihre Konten in einer Währung, zum heutigen Kurs.",
                         loanQuestion: "Was, wenn ich %@ vom Kredit vorzeitig tilge?",
                         loanReply: "Zahlen Sie das jetzt, ist der Kredit früher abbezahlt und kostet weniger Zinsen.",
                         interestSaved: "Gesparte Zinsen", monthsSooner: "Monate früher")
        case "es":
            return .init(perMonth: "Al mes", total: "Total",
                         subscriptionsReply: "Estas son todas tus suscripciones y lo que cuestan al mes.",
                         currenciesQuestion: "¿Cuánto dinero tengo en todas mis monedas?",
                         currenciesReply: "Todas tus cuentas en una sola moneda, al tipo de cambio de hoy.",
                         loanQuestion: "¿Y si adelanto %@ del préstamo?",
                         loanReply: "Si lo pagas ahora, terminas antes el préstamo y pagas menos intereses.",
                         interestSaved: "Ahorro en intereses", monthsSooner: "Meses antes")
        case "fr":
            return .init(perMonth: "Par mois", total: "Total",
                         subscriptionsReply: "Voici tous vos abonnements et ce qu'ils coûtent par mois.",
                         currenciesQuestion: "Combien d'argent ai-je dans toutes mes devises ?",
                         currenciesReply: "Tous vos comptes dans une seule devise, au taux du jour.",
                         loanQuestion: "Et si je rembourse %@ de mon crédit en avance ?",
                         loanReply: "En versant cette somme maintenant, le crédit se termine plus tôt et coûte moins d'intérêts.",
                         interestSaved: "Intérêts économisés", monthsSooner: "Mois gagnés")
        case "tr":
            return .init(perMonth: "Aylık", total: "Toplam",
                         subscriptionsReply: "İşte tüm aboneliklerin ve aylık tutarları.",
                         currenciesQuestion: "Tüm para birimlerinde ne kadar param var?",
                         currenciesReply: "Tüm hesapların tek para biriminde, bugünkü kurla.",
                         loanQuestion: "Krediye şimdi %@ erken ödeme yapsam ne olur?",
                         loanReply: "Bunu şimdi ödersen kredi daha erken biter ve daha az faiz ödersin.",
                         interestSaved: "Faiz tasarrufu", monthsSooner: "Kaç ay erken")
        case "pt":
            return .init(perMonth: "Por mês", total: "Total",
                         subscriptionsReply: "Aqui estão todas as suas assinaturas e quanto custam por mês.",
                         currenciesQuestion: "Quanto dinheiro eu tenho em todas as moedas?",
                         currenciesReply: "Todas as suas contas em uma moeda só, pela cotação de hoje.",
                         loanQuestion: "E se eu adiantar %@ do empréstimo?",
                         loanReply: "Se pagar agora, o empréstimo acaba antes e você paga menos juros.",
                         interestSaved: "Economia de juros", monthsSooner: "Meses a menos")
        case "it":
            return .init(perMonth: "Al mese", total: "Totale",
                         subscriptionsReply: "Ecco tutti i tuoi abbonamenti e quanto costano al mese.",
                         currenciesQuestion: "Quanti soldi ho in tutte le valute?",
                         currenciesReply: "Tutti i tuoi conti in un'unica valuta, al cambio di oggi.",
                         loanQuestion: "E se anticipassi %@ del prestito?",
                         loanReply: "Se lo versi ora, il prestito finisce prima e paghi meno interessi.",
                         interestSaved: "Interessi risparmiati", monthsSooner: "Mesi in meno")
        case "uk":
            return .init(perMonth: "На місяць", total: "Усього",
                         subscriptionsReply: "Ось усі ваші підписки і скільки вони коштують на місяць.",
                         currenciesQuestion: "Скільки в мене грошей у всіх валютах?",
                         currenciesReply: "Усі ваші рахунки в одній валюті, за сьогоднішнім курсом.",
                         loanQuestion: "А якщо внести %@ за кредитом достроково?",
                         loanReply: "Якщо внести цю суму зараз, кредит закриється раніше, а переплата зменшиться.",
                         interestSaved: "Економія на відсотках", monthsSooner: "Строк скоротиться, міс.")
        case "ja":
            return .init(perMonth: "月額", total: "合計",
                         subscriptionsReply: "すべてのサブスクと、毎月かかる金額です。",
                         currenciesQuestion: "全部の通貨でお金はいくらある？",
                         currenciesReply: "すべての口座を、今日のレートで1つの通貨にまとめました。",
                         loanQuestion: "ローンを%@繰り上げ返済したらどうなる？",
                         loanReply: "今これを返済すると完済が早まり、利息も減ります。",
                         interestSaved: "節約できる利息", monthsSooner: "短縮される月数")
        case "ko":
            return .init(perMonth: "월 합계", total: "합계",
                         subscriptionsReply: "모든 구독과 매달 나가는 금액이에요.",
                         currenciesQuestion: "모든 통화로 돈이 얼마나 있어?",
                         currenciesReply: "모든 계좌를 오늘 환율로 한 통화로 모았어요.",
                         loanQuestion: "대출을 %@ 중도 상환하면 어떻게 돼?",
                         loanReply: "지금 상환하면 대출이 더 빨리 끝나고 이자도 줄어요.",
                         interestSaved: "아끼는 이자", monthsSooner: "단축되는 개월 수")
        case "ru":
            return .init(perMonth: "В месяц", total: "Всего",
                         subscriptionsReply: "Вот все ваши подписки и сколько они стоят в месяц.",
                         currenciesQuestion: "Сколько у меня денег во всех валютах?",
                         currenciesReply: "Все ваши счета в одной валюте, по курсу на сегодня.",
                         loanQuestion: "Что если внести %@ по кредиту досрочно?",
                         loanReply: "Если внести эту сумму сейчас, кредит закроется раньше, а переплата станет меньше.",
                         interestSaved: "Экономия на процентах", monthsSooner: "Срок сократится, мес.")
        default:
            return .init(perMonth: "Per month", total: "Total",
                         subscriptionsReply: "Here are all your subscriptions and what they cost each month.",
                         currenciesQuestion: "How much money do I have in all currencies?",
                         currenciesReply: "All your accounts in one currency, at today's rate.",
                         loanQuestion: "What if I pay %@ off my loan early?",
                         loanReply: "Pay this now and the loan ends sooner, with less interest overall.",
                         interestSaved: "Interest saved", monthsSooner: "Months sooner")
        }
    }
}

#endif
