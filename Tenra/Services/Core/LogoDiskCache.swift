//
//  LogoDiskCache.swift
//  Tenra
//
//  Created on 2024
//

import Foundation
import UIKit

/// Кеш логотипов на диске
final class LogoDiskCache {
    static let shared = LogoDiskCache()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    /// Bump this when cache format changes or stale data needs clearing.
    /// Changing this wipes the entire logo disk cache on next launch.
    private static let cacheVersion = 4 // v4: switch from Supabase to jsDelivr — re-resolve all entries

    private init() {
        // Используем Application Support / logos
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("logos", isDirectory: true)

        // Создаем директорию при инициализации
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Invalidate stale cache when version bumps
        let versionKey = "LogoDiskCacheVersion"
        let stored = UserDefaults.standard.integer(forKey: versionKey)
        if stored < Self.cacheVersion {
            clearCache()
            UserDefaults.standard.set(Self.cacheVersion, forKey: versionKey)
        }
    }
    
    /// Получает безопасное имя файла из brandName
    private func safeFileName(for brandName: String) -> String {
        // Удаляем недопустимые символы для имени файла
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = brandName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: allowed.inverted)
            .joined(separator: "_")
            .lowercased()
        
        return safe.isEmpty ? "default" : safe
    }
    
    /// Получает путь к файлу логотипа
    private func fileURL(for brandName: String) -> URL {
        let fileName = safeFileName(for: brandName) + ".png"
        return cacheDirectory.appendingPathComponent(fileName)
    }
    
    /// Сохраняет изображение в кеш
    /// - Parameters:
    ///   - image: Изображение для сохранения
    ///   - brandName: Название бренда
    func save(_ image: UIImage, for brandName: String) {
        guard let data = image.pngData() else { return }
        
        let url = fileURL(for: brandName)
        
        // Сохраняем асинхронно на background queue
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: url)
        }
    }
    
    /// Загружает изображение из кеша
    /// - Parameter brandName: Название бренда
    /// - Returns: Изображение или nil, если не найдено
    func load(for brandName: String) -> UIImage? {
        let url = fileURL(for: brandName)
        
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    /// Проверяет наличие файла в кеше
    /// - Parameter brandName: Название бренда
    /// - Returns: true, если файл существует
    func exists(for brandName: String) -> Bool {
        let url = fileURL(for: brandName)
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Очищает весь кеш (для отладки/тестирования)
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
