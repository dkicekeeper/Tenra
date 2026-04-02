//
//  LogoDevConfig.swift
//  AIFinanceManager
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
}
