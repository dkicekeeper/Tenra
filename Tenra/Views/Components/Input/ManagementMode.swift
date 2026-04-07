//
//  ManagementMode.swift
//  Tenra
//

import SwiftUI

enum ManagementMode: Equatable {
    case normal
    case selecting
    case reordering

    var editMode: EditMode {
        switch self {
        case .normal: return .inactive
        case .selecting, .reordering: return .active
        }
    }

    var isSelecting: Bool { self == .selecting }
    var isReordering: Bool { self == .reordering }
}
