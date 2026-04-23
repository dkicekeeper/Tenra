//
//  EntityDetailTypes.swift
//  Tenra
//
//  Value types consumed by EntityDetailScaffold + HeroSection.
//

import SwiftUI

/// Primary / secondary action button config for EntityDetailScaffold's actions bar.
struct ActionConfig: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

/// Declarative info row (wraps UniversalRow(.info) at render time).
/// Use `icon` for SF Symbol; brand/custom icons pass through `iconConfig` escape hatch.
struct InfoRowConfig: Identifiable {
    let id = UUID()
    let icon: String?
    let label: String
    let value: String
    let iconColor: Color
    let trailing: AnyView?

    init(
        icon: String? = nil,
        label: String,
        value: String,
        iconColor: Color = AppColors.accent,
        trailing: AnyView? = nil
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.iconColor = iconColor
        self.trailing = trailing
    }
}

/// Linear progress strip rendered under the primary amount in HeroSection.
/// Used for: category budget utilization, loan % paid off.
struct ProgressConfig {
    let current: Double
    let total: Double
    let label: String?
    let color: Color

    init(current: Double, total: Double, label: String? = nil, color: Color = AppColors.accent) {
        self.current = current
        self.total = total
        self.label = label
        self.color = color
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(current / total, 0), 1)
    }
}
