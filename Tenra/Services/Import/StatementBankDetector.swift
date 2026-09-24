//
//  StatementBankDetector.swift
//  Tenra
//
//  Which of the user's accounts a statement belongs to. Every row of the review
//  screen used to default to the first account in its currency, so a user with a
//  Kaspi and a Freedom account in tenge had a Freedom statement land on Kaspi
//  unless they re-picked the account on every row, and the transfer matcher could
//  not tell the two sides of a transfer apart.
//
//  Banks print their web domain on every page ("www.kaspi.kz",
//  "www.bankffin.kz"). The domain is matched against the bank entries of
//  `ServiceLogoRegistry`, then against the account's logo or name. Bank NAMES are
//  deliberately not searched in the text: a Freedom statement contains
//  "KASPI MAGAZIN" purchases and a Kaspi one mentions "Freedom Bank" transfers.
//

import Foundation

nonisolated enum StatementBankDetector {

    /// The registry domain of the bank whose domain appears most often in `lines`.
    static func bankDomain(in lines: [String]) -> String? {
        let text = lines.joined(separator: "\n").lowercased()
        var best: (domain: String, count: Int)?
        for entry in ServiceLogoRegistry.services(for: .banks) {
            let count = text.components(separatedBy: entry.domain).count - 1
            guard count > 0 else { continue }
            if best.map({ count > $0.count || (count == $0.count && entry.domain < $0.domain) }) ?? true {
                best = (entry.domain, count)
            }
        }
        return best?.domain
    }

    /// The account among `accounts` that belongs to the bank `domain`: its logo is
    /// that bank's, or its name contains the bank's name ("Kaspi Gold", "Фридом").
    /// nil when none or several accounts qualify equally.
    static func accountId(forBankDomain domain: String, among accounts: [(id: String, name: String, logoDomain: String?)]) -> String? {
        guard let entry = ServiceLogoRegistry.services(for: .banks).first(where: { $0.domain == domain }) else {
            return nil
        }
        let byLogo = accounts.filter { $0.logoDomain == domain }
        if byLogo.count == 1 { return byLogo[0].id }

        let nameTokens = ([entry.displayName.split(separator: " ").first.map(String.init) ?? ""] + entry.aliases)
            .map { $0.lowercased() }
            .filter { $0.count >= 3 }
        let pool = byLogo.isEmpty ? accounts : byLogo
        let byName = pool.filter { account in
            let name = account.name.lowercased()
            return nameTokens.contains { name.contains($0) }
        }
        return byName.count == 1 ? byName[0].id : nil
    }
}
