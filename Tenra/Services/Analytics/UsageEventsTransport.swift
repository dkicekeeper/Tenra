//
//  UsageEventsTransport.swift
//  Tenra
//
//  Where UsageEvents' batches go: `POST /v1/events` on Tenra's server, the assistant's Worker
//  (AgentConfig.serverURL). No App Attest and no header that could tell installs apart: the
//  body is the batch and nothing else.
//

import Foundation

nonisolated protocol UsageEventsTransport: Sendable {
    func send(_ events: [UsageEvent]) async throws
}

/// The server answered and refused the batch.
nonisolated enum UsageSendError: Error, Equatable {
    case rejected(status: Int)

    /// A refusal that will not change by waiting: not the rate limit.
    var dropsBatch: Bool {
        switch self {
        case .rejected(let status): status != 429
        }
    }
}

nonisolated struct HTTPUsageTransport: UsageEventsTransport {
    let url: URL
    let session: URLSession

    /// nil without the server's address (a build without it, previews).
    static func make() -> HTTPUsageTransport? {
        AgentConfig.serverURL.map { HTTPUsageTransport(url: $0.appending(path: "v1/events"), session: .shared) }
    }

    func send(_ events: [UsageEvent]) async throws {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["events": events])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw UsageSendError.rejected(status: http.statusCode) }
    }
}
