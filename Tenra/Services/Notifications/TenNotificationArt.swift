//
//  TenNotificationArt.swift
//  Tenra
//
//  Ten's still picture on the notifications Tenra sends (DesignKit 5.3.0
//  `ParticleCreature.image`): an insight signal and the weekly digest read as a message from
//  Ten, as the same message does on Home (AssistantNoticeCard), in the same mood. The picture is
//  drawn when the notification is scheduled, in the appearance the phone has then.
//

import SwiftUI
import UserNotifications

enum TenNotificationArt {
    /// The picture's side in points (drawn at 3x).
    static let side: CGFloat = 120

    /// A fresh attachment of Ten in `mood`, or nil when it cannot be drawn or written: the
    /// notification then goes without it.
    static func attachment(mood: ParticleCreature.Mood) -> UNNotificationAttachment? {
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        guard let image = ParticleCreature.image(mood: mood, side: side, colorScheme: dark ? .dark : .light),
              let data = image.pngData() else { return nil }
        // Adding the notification moves the file into the system's store: a copy of its own
        // each time.
        let url = FileManager.default.temporaryDirectory.appending(path: "ten-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "ten", url: url, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
