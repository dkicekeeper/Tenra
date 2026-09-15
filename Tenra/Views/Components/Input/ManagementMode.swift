//
//  ManagementMode.swift
//  Tenra
//

import SwiftUI

enum ManagementMode: Equatable {
    case normal
    case selecting
    case reordering

    /// Only reordering needs the system edit mode (it draws the iOS 26 drag handles).
    ///
    /// Selecting deliberately stays `.inactive`: the management rows are `Button`-rooted,
    /// so `List(selection:)` never received their taps — edit mode only produced a list
    /// that looked selectable and was not. Bulk selection is driven by the row action and
    /// shown by `SelectionIndicator` instead.
    var editMode: EditMode {
        switch self {
        case .normal, .selecting: return .inactive
        case .reordering: return .active
        }
    }

    var isSelecting: Bool { self == .selecting }
    var isReordering: Bool { self == .reordering }
}
