//
//  IntelligenceAvailability.swift
//  Tenra
//
//  Single place that touches SystemLanguageModel availability, so the rest of
//  the import pipeline never imports FoundationModels and stays testable.
//
//  Apple Intelligence is unavailable on iPhone 14 and older, when the user has
//  not enabled it, and while assets are still downloading. Every one of those
//  is a normal state, not an error: the deterministic path handles them.
//

import Foundation
import FoundationModels

nonisolated enum IntelligenceStatus: Sendable, Equatable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady

    /// Localization key for the UI hint explaining reduced capability.
    var explanationKey: String? {
        switch self {
        case .available: return nil
        case .deviceNotEligible: return "import.intelligence.deviceNotEligible"
        case .notEnabled: return "import.intelligence.notEnabled"
        case .modelNotReady: return "import.intelligence.modelNotReady"
        }
    }
}

nonisolated enum IntelligenceAvailability {

    static var status: IntelligenceStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
    }

    static var isAvailable: Bool { status == .available }
}
