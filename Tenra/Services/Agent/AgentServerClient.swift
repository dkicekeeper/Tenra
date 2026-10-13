//
//  AgentServerClient.swift
//  Tenra
//
//  Calls the assistant Worker (`POST /v1/turn`) and streams its server-sent events. Network
//  work runs off the main actor (docs/concurrency.md). The base URL comes from Info.plist
//  (`TenraAssistantURL`); without it the cloud brain is off.
//

import Foundation

nonisolated protocol AgentTransport: Sendable {
    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error>
}

nonisolated enum AgentServerError: Error, Equatable {
    case notConfigured
    case unauthorized
    case invalidRequest(reason: String?)
    case quotaExceeded(limit: Int?)
    case busy
    case regionUnavailable
    case disabled
    case entitlementUnavailable
    case http(status: Int)

    /// The error body the Worker returns before streaming (`{"error": ..., "reason": ...}`).
    private struct Body: Decodable {
        let error: String
        let reason: String?
        let limit: Int?
    }

    static func from(status: Int, body: Data) -> AgentServerError {
        let parsed = try? JSONDecoder().decode(Body.self, from: body)
        switch status {
        case 400: return .invalidRequest(reason: parsed?.reason)
        case 401: return .unauthorized
        case 429: return parsed?.error == "quota" ? .quotaExceeded(limit: parsed?.limit) : .busy
        case 451: return .regionUnavailable
        case 502: return .entitlementUnavailable
        case 503: return .disabled
        default: return .http(status: status)
        }
    }
}

nonisolated enum AgentConfig {
    static var serverURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TenraAssistantURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }
}

nonisolated final class AgentServerClient: AgentTransport {
    private let baseURL: URL
    private let session: URLSession
    private let userID: @Sendable () async -> String?

    /// - Parameter userID: the RevenueCat app user id (`PremiumManager.appUserID`); the Worker
    ///   checks the `pro` entitlement for it.
    init(baseURL: URL, session: URLSession = .shared, userID: @escaping @Sendable () async -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.userID = userID
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let baseURL = self.baseURL, session = self.session, userID = self.userID
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let user = await userID() else { throw AgentServerError.unauthorized }
                    var request = URLRequest(url: baseURL.appending(path: "v1/turn"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(user, forHTTPHeaderField: "x-tenra-user")
                    request.httpBody = try JSONEncoder().encode(AgentTurnRequest(messages: messages))

                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 4096 { break }
                        }
                        throw AgentServerError.from(status: status, body: body)
                    }
                    var parser = AgentSSEParser()
                    for try await line in bytes.lines {
                        if let event = parser.feed(line: line) { continuation.yield(event) }
                    }
                    if let event = parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
