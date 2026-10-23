//
//  AgentServerClient.swift
//  Tenra
//
//  Calls the assistant Worker (`POST /v1/turn`) and streams its server-sent events. Network
//  work runs off the main actor (docs/concurrency.md). The base URL comes from Info.plist
//  (`TenraAssistantURL`); without it the cloud brain is off. With App Attest every body is
//  signed (AgentAttestation); the server needs that from people without Pro.
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
    /// App Attest was missing or refused (`reason` from the server, or "unsupported").
    case attestation(reason: String?)
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
        // A key registration the server refused (POST /v1/attest) is App Attest's; any other
        // 400 is the request itself (its size, its fields), which a resend does not fix.
        case 400: return parsed?.error == "attestation" ? .attestation(reason: parsed?.reason) : .invalidRequest(reason: parsed?.reason)
        case 401: return parsed?.error == "attest" ? .attestation(reason: parsed?.reason) : .unauthorized
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
    private let attestation: AgentAttestation?

    /// - Parameters:
    ///   - userID: the RevenueCat app user id (`PremiumManager.appUserID`); the Worker checks
    ///     the `pro` entitlement for it.
    ///   - attestation: signs each request with App Attest; nil where it is not supported.
    init(baseURL: URL, session: URLSession = .shared, attestation: AgentAttestation? = nil, userID: @escaping @Sendable () async -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.attestation = attestation
        self.userID = userID
    }

    func turn(_ messages: [AgentWireMessage]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let baseURL = self.baseURL, session = self.session, userID = self.userID, attestation = self.attestation
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let user = await userID() else { throw AgentServerError.unauthorized }
                    let body = try JSONEncoder().encode(AgentTurnRequest(messages: messages, user: user))
                    var bytes = try await Self.send(body, user: user, baseURL: baseURL, session: session, attestation: attestation)
                    if case .failure(let error) = bytes, error == .attestation(reason: "unknown_key"), let attestation {
                        // The server lost the key (or never had it): register a new one, once.
                        await attestation.reset()
                        bytes = try await Self.send(body, user: user, baseURL: baseURL, session: session, attestation: attestation)
                    }
                    let stream = try bytes.get()
                    var parser = AgentSSEParser()
                    for try await line in stream.lines {
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

    /// One POST: the stream on 200, the server's error otherwise.
    private static func send(
        _ body: Data,
        user: String,
        baseURL: URL,
        session: URLSession,
        attestation: AgentAttestation?
    ) async throws -> Result<URLSession.AsyncBytes, AgentServerError> {
        var request = URLRequest(url: baseURL.appending(path: "v1/turn"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(user, forHTTPHeaderField: "x-tenra-user")
        request.httpBody = body
        if let attestation {
            // Without a signature the server refuses the turn (401 attest), Pro or not. A failure
            // here (no network while registering the key, Apple's service down) is thrown as it
            // is, so the person sees "offline" or "try again", not a permanent refusal.
            let headers = try await attestation.headers(for: body)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        }

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4096 { break }
            }
            return .failure(AgentServerError.from(status: status, body: data))
        }
        return .success(bytes)
    }
}
