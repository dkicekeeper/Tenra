//
//  DiagnosticPayloadStoreTests.swift
//  TenraTests
//
//  Pins the on-disk store for MetricKit payloads: the JSON is kept as delivered, listing is
//  newest first, and only the latest `maxPayloads` survive (older files are deleted).
//  Each test uses its own temporary directory, so no process-global state is shared.
//

import Foundation
import Testing
@testable import Tenra

struct DiagnosticPayloadStoreTests {

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DiagnosticPayloadStoreTests-\(UUID().uuidString)", isDirectory: true)
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func save(_ store: DiagnosticPayloadStore, index: Int) throws -> DiagnosticPayloadSummary {
        try store.save(
            json: Data(#"{"n":\#(index)}"#.utf8),
            periodStart: start,
            periodEnd: start.addingTimeInterval(86_400),
            counts: .init(crashes: index),
            receivedAt: start.addingTimeInterval(Double(index) * 60)
        )
    }

    @Test("An empty store lists nothing")
    func empty() {
        #expect(DiagnosticPayloadStore(directory: directory).summaries().isEmpty)
    }

    @Test("A saved payload keeps its JSON and lists with its counts")
    func saveAndList() throws {
        let store = DiagnosticPayloadStore(directory: directory)
        defer { try? store.removeAll() }

        let saved = try save(store, index: 2)
        let listed = store.summaries()

        #expect(listed == [saved])
        #expect(listed.first?.counts.crashes == 2)
        #expect(try Data(contentsOf: store.fileURL(for: saved)) == Data(#"{"n":2}"#.utf8))
    }

    @Test("Only the newest payloads are kept, newest first, and older files are deleted")
    func keepsTheLatest() throws {
        let store = DiagnosticPayloadStore(directory: directory, maxPayloads: 3)
        defer { try? store.removeAll() }

        let saved = try (0..<5).map { try save(store, index: $0) }
        let listed = store.summaries()

        #expect(listed.map(\.counts.crashes) == [4, 3, 2])
        for dropped in saved.prefix(2) {
            #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: dropped).path))
        }
    }

    @Test("removeAll deletes every payload")
    func removeAll() throws {
        let store = DiagnosticPayloadStore(directory: directory)
        _ = try save(store, index: 1)

        try store.removeAll()

        #expect(store.summaries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
