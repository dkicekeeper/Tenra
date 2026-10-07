//
//  SupportContact.swift
//  Tenra
//
//  The support inbox and the `mailto:` link the app opens to reach it (the rating survey's
//  "not really" path, the database error screen). Keep the address in sync with the
//  support page's contact e-mail.
//

import Foundation
import UIKit

enum SupportContact {

    static let email = "dakacom@gmail.com"

    /// A `mailto:` URL whose body ends with the app version, build and iOS version, after any
    /// `details` (an error code, for example) the user can read before sending.
    static func mailURL(subject: String, details: String? = nil) -> URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var footer = ["Tenra \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)"]
        if let details, !details.isEmpty { footer.insert(details, at: 0) }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\n\n--\n" + footer.joined(separator: "\n"))
        ]
        return components.url
    }
}
