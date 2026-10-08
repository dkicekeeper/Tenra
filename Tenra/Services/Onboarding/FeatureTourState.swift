//
//  FeatureTourState.swift
//  Tenra
//
//  UserDefaults-backed "already shown" flags for the one-time feature hints (DesignKit's
//  `.spotlight`): each hint shows once, the first time its feature is on screen.
//

import Foundation

enum FeatureTourState {
    enum Hint: String, Hashable {
        /// The voice orb is the stop button (voice input).
        case voiceStopOrb = "featureTour.voiceStopOrb"
    }

    static func hasSeen(_ hint: Hint) -> Bool {
        UserDefaults.standard.bool(forKey: hint.rawValue)
    }

    static func markSeen(_ hint: Hint) {
        UserDefaults.standard.set(true, forKey: hint.rawValue)
    }
}
