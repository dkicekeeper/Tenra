//
//  ICloudBackupAskCard.swift
//  Tenra
//
//  The one-time ask on Home for installs from before iCloud backups were on by default (1.7):
//  the weekly backup lives only on this iPhone until it goes to iCloud Drive. "Turn on" moves
//  the backups there, ✕ keeps them local; either way it never shows again
//  (CloudSyncViewModel.shouldAskForICloud, answerICloudAsk).
//

import SwiftUI

struct ICloudBackupAskCard: View {
    let onTurnOn: () -> Void
    let onHide: () -> Void

    var body: some View {
        NoticeCard(
            title: String(localized: "home.iCloudAsk.title"),
            message: String(localized: "home.iCloudAsk.message"),
            actionTitle: String(localized: "home.iCloudAsk.action"),
            actionSystemImage: "icloud",
            action: onTurnOn,
            hideLabel: String(localized: "assistant.notice.hide"),
            onHide: onHide
        ) {
            Icon(
                source: .sfSymbol("icloud.fill"),
                style: .circle(
                    size: NoticeCardMetrics.leadingSize,
                    tint: .monochrome(AppColors.accent),
                    backgroundColor: AppColors.accent.opacity(0.15)
                )
            )
        }
    }
}

#Preview {
    ICloudBackupAskCard(onTurnOn: {}, onHide: {})
        .screenPadding()
}
