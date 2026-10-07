//
//  DiagnosticPayloadStore.swift
//  Tenra
//
//  Keeps the latest MetricKit diagnostic payloads (crashes, hangs, disk-write and CPU
//  exceptions, slow launches) on disk, in Application Support/Diagnostics, so the owner can
//  read them from Settings → Diagnostics and a user can share them. There is no backend:
//  nothing leaves the device unless the user shares it.
//
//  Each payload is saved as MetricKit's own JSON (`jsonRepresentation()`), next to an index
//  with the per-kind counts read from the typed payload, so listing never parses the JSON.
//  Foundation only (MetricKitCollector does the MetricKit part), thread-safe: MetricKit
//  delivers on a background queue while the Settings screen may be reading.
//

import Foundation

/// One saved payload, as listed in Settings → Diagnostics.
nonisolated struct DiagnosticPayloadSummary: Codable, Equatable, Sendable, Identifiable {
    var id: String { fileName }

    let fileName: String
    let receivedAt: Date
    /// The period the payload covers (`timeStampBegin` / `timeStampEnd`).
    let periodStart: Date
    let periodEnd: Date
    let counts: Counts

    struct Counts: Codable, Equatable, Sendable {
        var crashes = 0
        var hangs = 0
        var diskWrites = 0
        var cpuExceptions = 0
        var slowLaunches = 0

        var total: Int { crashes + hangs + diskWrites + cpuExceptions + slowLaunches }
    }
}

nonisolated final class DiagnosticPayloadStore: @unchecked Sendable {

    static let defaultMaxPayloads = 20

    /// Application Support/Diagnostics.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    let directory: URL
    let maxPayloads: Int

    /// Serialises index read-modify-write and file pruning.
    private let lock = NSLock()
    private static let indexFileName = "index.json"

    init(directory: URL = DiagnosticPayloadStore.defaultDirectory, maxPayloads: Int = defaultMaxPayloads) {
        self.directory = directory
        self.maxPayloads = max(1, maxPayloads)
    }

    // MARK: - Writing

    /// Saves one payload's JSON and records it in the index; the oldest beyond `maxPayloads`
    /// are deleted.
    @discardableResult
    func save(
        json: Data,
        periodStart: Date,
        periodEnd: Date,
        counts: DiagnosticPayloadSummary.Counts,
        receivedAt: Date = Date()
    ) throws -> DiagnosticPayloadSummary {
        lock.lock()
        defer { lock.unlock() }

        try prepareDirectory()
        let summary = DiagnosticPayloadSummary(
            fileName: Self.fileName(for: receivedAt),
            receivedAt: receivedAt,
            periodStart: periodStart,
            periodEnd: periodEnd,
            counts: counts
        )
        try json.write(to: directory.appendingPathComponent(summary.fileName), options: .atomic)

        var index = loadIndex()
        index.append(summary)
        index.sort { $0.receivedAt > $1.receivedAt }
        let kept = Array(index.prefix(maxPayloads))
        for dropped in index.dropFirst(maxPayloads) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(dropped.fileName))
        }
        try writeIndex(kept)
        return summary
    }

    /// Deletes every saved payload and the index.
    func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Reading

    /// Saved payloads, newest first. Entries whose file has gone are skipped.
    func summaries() -> [DiagnosticPayloadSummary] {
        lock.lock()
        defer { lock.unlock() }
        return loadIndex()
            .filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    func fileURL(for summary: DiagnosticPayloadSummary) -> URL {
        directory.appendingPathComponent(summary.fileName)
    }

    // MARK: - Private

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        // Diagnostics are about this install, not user data: keep them out of device backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
        #endif
    }

    private var indexURL: URL { directory.appendingPathComponent(Self.indexFileName) }

    private func loadIndex() -> [DiagnosticPayloadSummary] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? Self.decoder.decode([DiagnosticPayloadSummary].self, from: data)) ?? []
    }

    private func writeIndex(_ index: [DiagnosticPayloadSummary]) throws {
        try Self.encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    /// "diagnostic-2026-10-06-153012-1a2b3c4d.json": sortable by name, unique per payload.
    private static func fileName(for date: Date) -> String {
        let stamp = fileNameFormatter.string(from: date)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return "diagnostic-\(stamp)-\(suffix).json"
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    // Default date strategy (seconds since the reference date, full precision): two payloads
    // delivered in the same second keep their order, and a summary round-trips unchanged.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
