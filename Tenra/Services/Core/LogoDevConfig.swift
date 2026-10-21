//
//  LogoDevConfig.swift
//  Tenra
//
//  Created on 2024
//

import Foundation

/// Конфигурация для logo.dev API
enum LogoDevConfig {
    /// Получает public key из Info.plist (nonisolated для использования из любого контекста)
    private nonisolated static var publicKey: String? {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["LOGO_DEV_PUBLIC_KEY"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }
    
    /// Проверяет, доступен ли сервис (есть public key)
    nonisolated static var isAvailable: Bool {
        publicKey != nil
    }
    
    /// Формирует URL для загрузки логотипа
    /// - Parameter brandName: Название бренда или домен
    /// - Returns: URL для загрузки логотипа или nil, если ключ отсутствует
    nonisolated static func logoURL(for brandName: String) -> URL? {
        guard let key = publicKey else {
            return nil
        }
        
        // Нормализуем brandName: убираем пробелы по краям
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedName.isEmpty else {
            return nil
        }
        
        // Percent encoding для безопасного URL
        guard let encodedBrandName = normalizedName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        
        // Формируем URL: https://img.logo.dev/{name}?token={key}
        let urlString = "https://img.logo.dev/\(encodedBrandName)?token=\(key)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        #if DEBUG
        #endif

        return url
    }

    /// The logo of a company found by its name ("Magnum Cash&Carry"), for a merchant
    /// without a known domain. `fallback=404`: an unknown name answers 404 instead of a
    /// generated monogram, so "no logo" is told apart from a logo.
    nonisolated static func nameLogoURL(for name: String) -> URL? {
        guard let key = publicKey else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "https://img.logo.dev/name/\(encoded)?token=\(key)&size=128&format=png&fallback=404")
    }
}
