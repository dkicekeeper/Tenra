//
//  IconSource.swift
//  AIFinanceManager
//
//  Unified icon/logo source model for all entities
//

import Foundation

/// Универсальный источник иконки/логотипа для всех сущностей
enum IconSource: Codable, Equatable, Hashable {
    case sfSymbol(String)           // SF Symbol иконка
    case brandService(String)       // Логотип бренда через provider chain

    private enum CodingKeys: String, CodingKey {
        case sfSymbol, brandService
    }
    private enum AssocCodingKeys: String, CodingKey { case _0 }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.sfSymbol) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .sfSymbol)
            self = .sfSymbol(try nested.decode(String.self, forKey: ._0))
        } else if container.contains(.brandService) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .brandService)
            self = .brandService(try nested.decode(String.self, forKey: ._0))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown IconSource case"))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sfSymbol(let name):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .sfSymbol)
            try nested.encode(name, forKey: ._0)
        case .brandService(let name):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .brandService)
            try nested.encode(name, forKey: ._0)
        }
    }

    /// Строковый идентификатор для сохранения
    var displayIdentifier: String {
        switch self {
        case .sfSymbol(let name):
            return "sf:\(name)"
        case .brandService(let name):
            return "brand:\(name)"
        }
    }

    /// Парсинг из строкового идентификатора
    static func from(displayIdentifier: String) -> IconSource? {
        if displayIdentifier.hasPrefix("sf:") {
            return .sfSymbol(String(displayIdentifier.dropFirst(3)))
        } else if displayIdentifier.hasPrefix("brand:") {
            return .brandService(String(displayIdentifier.dropFirst(6)))
        }
        return nil
    }
}
