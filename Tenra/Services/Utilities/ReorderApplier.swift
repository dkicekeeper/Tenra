//
//  ReorderApplier.swift
//  Tenra
//
//  Applies a drag-to-reorder result to an ordered array.
//
//  Deliberately free of SwiftUI types: `ReorderDifference` (iOS 27) has no public
//  initializer, so logic expressed against it cannot be unit-tested at all. The
//  SwiftUI adapter lives in `Extensions/ReorderDifference+Apply.swift` and does
//  nothing but translate; everything that decides final order is here, under test.
//
//  Order is persisted (account and category order both round-trip through CoreData),
//  so a silent mistake here is a visible one for the user.
//

import Foundation

nonisolated enum ReorderApplier {

    /// Where the moved items land. Mirrors `ReorderDifference.Destination.Position`.
    enum Destination<ID: Hashable>: Equatable {
        /// Insert the moved items directly before this item.
        case before(ID)
        /// Append the moved items to the end.
        case end
    }

    /// Returns `collection` with `sources` lifted out and re-inserted at `destination`.
    ///
    /// The moved items keep their relative order. Ids that are not in the collection are
    /// ignored; if none of them match, the collection comes back unchanged. When the
    /// destination item is itself being moved, the items land where it used to be.
    static func reordered<Element: Identifiable>(
        _ collection: [Element],
        moving sources: [Element.ID],
        to destination: Destination<Element.ID>
    ) -> [Element] {
        let moving = Set(sources)
        guard !moving.isEmpty else { return collection }

        var remaining: [Element] = []
        var moved: [Element] = []
        remaining.reserveCapacity(collection.count)
        moved.reserveCapacity(moving.count)

        for element in collection {
            if moving.contains(element.id) {
                moved.append(element)
            } else {
                remaining.append(element)
            }
        }

        guard !moved.isEmpty else { return collection }

        switch destination {
        case .before(let id):
            // `firstIndex` is nil when the anchor is one of the moved items (it is no
            // longer in `remaining`); appending matches what the drag showed.
            let index = remaining.firstIndex { $0.id == id } ?? remaining.endIndex
            remaining.insert(contentsOf: moved, at: index)
        case .end:
            remaining.append(contentsOf: moved)
        }

        return remaining
    }
}
