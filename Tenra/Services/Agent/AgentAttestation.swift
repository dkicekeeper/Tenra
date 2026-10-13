//
//  AgentAttestation.swift
//  Tenra
//
//  App Attest for the assistant (server/assistant/src/appattest.ts): proof for the server that
//  a request comes from this app on a real Apple device. It is what lets people without Pro use
//  the cloud brain, their free quota being counted per attested key.
//
//  Once per install: a Secure Enclave key (DCAppAttestService), a challenge from the server,
//  Apple's attestation of the key for that challenge, POST /v1/attest. Then every request body
//  is signed (an assertion) and sent in x-tenra-key / x-tenra-assertion. The key id lives in
//  UserDefaults: App Attest keys do not survive a reinstall, and neither do defaults.
//

import CryptoKit
import DeviceCheck
import Foundation

actor AgentAttestation {
    nonisolated static let keyIdDefaultsKey = "assistant.appAttestKeyId"

    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private var registering: Task<String, Error>?

    init(baseURL: URL, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
    }

    /// False in the Simulator and on devices without the Secure Enclave support App Attest needs.
    nonisolated static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// The headers that prove `body` comes from this app on this device.
    func headers(for body: Data) async throws -> [String: String] {
        let keyId = try await registeredKey()
        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: Data(SHA256.hash(data: body)))
            return ["x-tenra-key": keyId, "x-tenra-assertion": assertion.base64EncodedString()]
        } catch let error as DCError where error.code == .invalidKey {
            // The key is gone (a restored backup, a reset Secure Enclave): make a new one.
            reset()
            let fresh = try await registeredKey()
            let assertion = try await DCAppAttestService.shared.generateAssertion(fresh, clientDataHash: Data(SHA256.hash(data: body)))
            return ["x-tenra-key": fresh, "x-tenra-assertion": assertion.base64EncodedString()]
        }
    }

    /// Forgets the key, so the next request registers a new one (the server did not know it).
    func reset() {
        defaults.removeObject(forKey: Self.keyIdDefaultsKey)
    }

    private func registeredKey() async throws -> String {
        if let keyId = defaults.string(forKey: Self.keyIdDefaultsKey) { return keyId }
        if let registering { return try await registering.value }
        let task = Task { try await self.register() }
        registering = task
        defer { registering = nil }
        let keyId = try await task.value
        defaults.set(keyId, forKey: Self.keyIdDefaultsKey)
        return keyId
    }

    private func register() async throws -> String {
        guard Self.isSupported else { throw AgentServerError.attestation(reason: "unsupported") }
        let keyId = try await DCAppAttestService.shared.generateKey()
        let challenge = try await fetchChallenge()
        let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))

        var request = URLRequest(url: baseURL.appending(path: "v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Registration(keyId: keyId, attestation: attestation.base64EncodedString(), challenge: challenge))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AgentServerError.from(status: status, body: data) }
        return keyId
    }

    private func fetchChallenge() async throws -> String {
        let (data, response) = try await session.data(from: baseURL.appending(path: "v1/attest/challenge"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AgentServerError.from(status: status, body: data) }
        return try JSONDecoder().decode(Challenge.self, from: data).challenge
    }

    private nonisolated struct Registration: Encodable {
        let keyId: String
        let attestation: String
        let challenge: String
    }

    private nonisolated struct Challenge: Decodable {
        let challenge: String
    }
}
