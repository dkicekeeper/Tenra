//
//  QuickAddControl.swift
//  TenraWidgets
//
//  "Log an expense" for Control Center, the Lock Screen and the Action button: opens Tenra on
//  tenra://add, which is the assistant's field where it runs ("coffee 1500" is parsed on the
//  phone, free), else Home's categories (AppCoordinator.handleDeepLink).
//

import AppIntents
import SwiftUI
import WidgetKit

struct QuickAddControl: ControlWidget {
    static let kind = "dakacom.Tenra.quickAdd"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(TodayWidgetView.addURL(category: nil))) {
                Label(String(localized: "widget.quickAdd.title"), systemImage: "plus.circle.fill")
            }
        }
        .displayName(LocalizedStringResource("widget.quickAdd.title"))
        .description(LocalizedStringResource("widget.quickAdd.description"))
    }
}
