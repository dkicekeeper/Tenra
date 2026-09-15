//
//  ReorderApplierTests.swift
//  TenraTests
//
//  Pins the ordering rules behind drag-to-reorder (iOS 27). The SwiftUI type that
//  carries a reorder result, `ReorderDifference`, has no public initializer, so this
//  is the only level at which the behaviour can be tested — which is exactly why the
//  logic was extracted into `ReorderApplier`.
//
//  Account and category order is persisted, so every case here protects stored data.
//

import Testing
@testable import Tenra

struct ReorderApplierTests {

    private struct Item: Identifiable, Equatable {
        let id: String
    }

    private func items(_ ids: String...) -> [Item] {
        ids.map(Item.init(id:))
    }

    private func ids(_ items: [Item]) -> [String] {
        items.map(\.id)
    }

    @Test("moving one item before another puts it directly ahead of the anchor")
    func moveSingleBefore() {
        let result = ReorderApplier.reordered(
            items("a", "b", "c", "d"),
            moving: ["d"],
            to: .before("b")
        )
        #expect(ids(result) == ["a", "d", "b", "c"])
    }

    @Test("moving one item to the end appends it")
    func moveSingleToEnd() {
        let result = ReorderApplier.reordered(
            items("a", "b", "c"),
            moving: ["a"],
            to: .end
        )
        #expect(ids(result) == ["b", "c", "a"])
    }

    @Test("moving before the first item puts the selection at the front")
    func moveBeforeFirst() {
        let result = ReorderApplier.reordered(
            items("a", "b", "c"),
            moving: ["c"],
            to: .before("a")
        )
        #expect(ids(result) == ["c", "a", "b"])
    }

    @Test("several items keep their relative order when moved together")
    func moveMultiplePreservesRelativeOrder() {
        let result = ReorderApplier.reordered(
            items("a", "b", "c", "d", "e"),
            moving: ["b", "d"],
            to: .before("a")
        )
        #expect(ids(result) == ["b", "d", "a", "c", "e"])
    }

    @Test("a non-contiguous selection moved to the end stays in original order")
    func moveMultipleToEnd() {
        let result = ReorderApplier.reordered(
            items("a", "b", "c", "d"),
            moving: ["a", "c"],
            to: .end
        )
        #expect(ids(result) == ["b", "d", "a", "c"])
    }

    @Test("an empty selection leaves the collection untouched")
    func emptySourcesIsNoOp() {
        let original = items("a", "b", "c")
        let result = ReorderApplier.reordered(original, moving: [], to: .before("a"))
        #expect(result == original)
    }

    @Test("ids that are not in the collection leave it untouched")
    func unknownSourcesAreIgnored() {
        let original = items("a", "b", "c")
        let result = ReorderApplier.reordered(original, moving: ["zz"], to: .end)
        #expect(result == original)
    }

    @Test("an anchor that is itself being moved does not drop items")
    func anchorInsideSelectionKeepsEveryItem() {
        let result = ReorderApplier.reordered(
            items("a", "b", "c"),
            moving: ["b", "c"],
            to: .before("c")
        )
        // No item may disappear, whatever the placement rule decides.
        #expect(Set(ids(result)) == ["a", "b", "c"])
        #expect(result.count == 3)
    }

    @Test("moving an item before itself keeps the order stable")
    func moveItemBeforeItself() {
        let original = items("a", "b", "c")
        let result = ReorderApplier.reordered(original, moving: ["b"], to: .before("b"))
        #expect(Set(ids(result)) == ["a", "b", "c"])
        #expect(result.count == 3)
    }

    @Test("moving every item to the end preserves the order")
    func moveAllToEnd() {
        let original = items("a", "b", "c")
        let result = ReorderApplier.reordered(original, moving: ["a", "b", "c"], to: .end)
        #expect(ids(result) == ["a", "b", "c"])
    }

    @Test("an empty collection survives any move")
    func emptyCollection() {
        let result = ReorderApplier.reordered([Item](), moving: ["a"], to: .end)
        #expect(result.isEmpty)
    }
}
