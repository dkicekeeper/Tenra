//
//  LocalLogoProvider.swift
//  AIFinanceManager
//
//  Checks BankLogo assets for local logo matches
//

import UIKit

/// Checks local BankLogo assets for matching domain.
nonisolated final class LocalLogoProvider: LogoProvider {
    let name = "local"

    private static let domainMap: [String: BankLogo] = {
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
            ("altynbank.kz", .altyn),
            ("kazpost.kz", .kazPost),
            ("alataucitybank.kz", .alatauCityBank),
        ]
        return Dictionary(uniqueKeysWithValues: mappings)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard let bankLogo = Self.domainMap[domain.lowercased()] else {
            return nil
        }
        return UIImage(named: bankLogo.rawValue)
    }
}
