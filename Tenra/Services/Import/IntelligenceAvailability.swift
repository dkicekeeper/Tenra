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

    /// Whether the on-device model accepts image input (iOS 27+).
    ///
    /// A probe, not yet a feature: if this is true on real devices, a receipt photo
    /// could go to the model directly instead of only its OCR text, which is the one
    /// case where layout carries meaning the text loses. Adopting that would have to
    /// cross the `DocumentSnapshot` seam (see docs/domains/import.md, rule 1), so the
    /// capability is measured before the design is chosen.
    ///
    /// False on iOS 26, on models without the capability, and whenever the model is
    /// unavailable — callers keep the text path either way.
    static var supportsVision: Bool {
        guard #available(iOS 27, *), isAvailable else { return false }
        return SystemLanguageModel.default.capabilities.contains(.vision)
    }
}
