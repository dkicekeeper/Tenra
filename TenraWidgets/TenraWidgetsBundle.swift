//
//  TenraWidgetsBundle.swift
//  TenraWidgets
//
//  The widget extension: "For today" on the Home Screen and the Lock Screen, and "Log an
//  expense" for Control Center. It reads only what the app wrote into the App Group
//  (WidgetData); the CoreData store stays the app's (docs/domains/intents.md §8).
//

import SwiftUI
import WidgetKit

@main
struct TenraWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        QuickAddControl()
    }
}
