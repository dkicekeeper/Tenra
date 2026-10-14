//
//  AgentFastPath.swift
//  Tenra
//
//  FastPath (docs/plan-ai-assistant.md §3.8): a message the phone's own parser understands as
//  income or expenses ("кофе 1500 и такси 2300") becomes a draft on the phone, the confirm card
//  without the cloud. The parser is the voice one (`VoiceInputParser.parseMulti`), the draft the
//  path every other draft takes (`TransactionDraftService.makeDraft`, FinanceToolkit).
//
//  The test is deliberately conservative: a question, a plan, a transfer, a regular payment, a
//  budget, or a part the parser could not read sends the message to the model, which drafts as
//  well. A record taken for a question costs one cloud answer; a question taken for a record
//  would answer with a wrong card.
//

import Foundation

enum AgentFastPath {
    /// Longer messages are rarely a plain record.
    static let maxLength = 160

    /// Whether the parse of `text` is a record the phone can draft by itself: every clause has
    /// an amount and a category, every operation is income or an expense, and nothing in the
    /// text asks, plans, moves money between accounts or repeats.
    static func isRecord(_ text: String, operations: [ParsedOperation], clauses: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength,
              !operations.isEmpty, operations.count == clauses,
              !readsAsQuestion(trimmed) else { return false }
        return operations.allSatisfy { operation in
            (operation.type == .expense || operation.type == .income)
                && (operation.amount ?? 0) > 0
                && operation.categoryName?.isEmpty == false
        }
    }

    /// A question mark, or a word that asks, plans, compares, moves money or repeats, in any of
    /// the app's languages. Words up to three letters match whole; longer ones as the start of
    /// a word, so their forms match too ("подписку", "budgets"). Scripts without spaces match
    /// anywhere.
    static func readsAsQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("?") || lowered.contains("？") { return true }
        let words = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let padded = " " + words.joined(separator: " ") + " "
        for marker in markers {
            if marker.contains(" ") {
                if padded.contains(" " + marker) { return true }
            } else if marker.count <= 3 {
                if words.contains(marker) { return true }
            } else if words.contains(where: { $0.hasPrefix(marker) }) {
                return true
            }
        }
        return unspacedMarkers.contains { lowered.contains($0) }
    }

    private static let markers: [String] = [
        // ru
        "сколько", "как", "какой", "какая", "какие", "почему", "зачем", "что", "где", "когда", "ли",
        "можно", "стоит", "нужно", "надо", "посоветуй", "совет", "помоги", "покажи", "расскажи",
        "сравни", "план", "бюджет", "лимит", "подписк", "кажд", "ежемесяч", "еженед",
        "в месяц", "в неделю", "в год", "накоп", "отлож", "инвест", "кредит", "ипотек", "рефинанс",
        "вклад", "депозит", "перевод", "перевел", "перевёл", "перекин", "прогноз", "если", "хочу",
        "сэконом", "эконом",
        // uk
        "скільки", "як", "чому", "що", "коли", "можна", "варто", "порадь", "допоможи", "ліміт",
        "підписк", "щомісяч", "кожн", "на місяць", "переказ", "відклад", "якщо", "заощад",
        // en
        "how", "what", "why", "when", "where", "which", "can", "could", "should", "would", "will",
        "is", "are", "do", "does", "did", "help", "show", "tell", "compare", "plan", "budget",
        "limit", "subscription", "every", "monthly", "weekly", "yearly", "per month", "a month",
        "save", "saving", "invest", "loan", "mortgage", "refinanc", "transfer", "moved", "forecast",
        "if", "want", "afford",
        // de
        "wie", "was", "warum", "wann", "welche", "kann", "soll", "sollte", "hilf", "zeig",
        "vergleich", "abo", "monatlich", "jeden", "pro monat", "spar", "kredit", "überweis", "wenn",
        "möchte",
        // es
        "cuánto", "cuanto", "cómo", "qué", "por qué", "cuándo", "dónde", "puedo", "debo", "debería",
        "ayuda", "muestra", "compara", "presupuesto", "límite", "suscripción", "cada", "mensual",
        "al mes", "ahorr", "invert", "préstamo", "crédito", "transferenc", "quiero",
        // fr
        "combien", "comment", "pourquoi", "quand", "quel", "quelle", "peux", "dois", "devrais",
        "aide", "montre", "abonnement", "chaque", "mensuel", "par mois", "épargn", "économis",
        "prêt", "virement", "veux",
        // it
        "quanto", "come", "perché", "quale", "posso", "devo", "dovrei", "aiuta", "mostra",
        "confronta", "abbonamento", "ogni", "mensile", "al mese", "risparmi", "prestito", "mutuo",
        "bonifico", "voglio",
        // pt-BR
        "quanto", "como", "por que", "onde", "qual", "deveria", "ajuda", "orçamento", "assinatura",
        "mensal", "por mês", "economiz", "guardar", "empréstimo", "financiamento", "transferi",
        "quero",
        // tr
        "kaç", "ne kadar", "nasıl", "neden", "niye", "ne zaman", "nerede", "hangi", "mı", "mi", "mu",
        "mü", "yardım", "göster", "karşılaştır", "bütçe", "abonelik", "her ay", "aylık", "biriktir",
        "yatırım", "kredi", "havale", "eğer", "istiyorum",
    ]

    /// Japanese and Korean: no spaces between words.
    private static let unspacedMarkers: [String] = [
        "いくら", "どう", "なぜ", "いつ", "どこ", "どの", "べき", "教え", "見せ", "比較", "予算", "上限",
        "サブスク", "毎月", "月額", "貯", "投資", "ローン", "振替", "振込", "もし", "したい",
        "얼마", "어떻게", "왜", "언제", "어디", "어느", "할까", "해야", "알려", "보여", "비교", "예산",
        "한도", "구독", "매달", "매월", "저축", "투자", "대출", "이체", "송금", "만약", "싶어",
    ]
}
