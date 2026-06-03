//
//  DisclosureChevron.swift
//  Tenra
//
//  Native iOS disclosure indicator for navigable rows that live OUTSIDE a `List`
//  (LazyVStack / ScrollView), where SwiftUI does not add one automatically.
//

import SwiftUI

/// The system disclosure chevron used to signal "tap to navigate forward".
///
/// Uses `chevron.forward` (locale / RTL-aware — flips in right-to-left layouts,
/// unlike a hardcoded `chevron.right`) with Apple's standard tertiary styling so
/// rows in `LazyVStack`/`ScrollView` match the look of a native `List` row.
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textTertiary)
            .accessibilityHidden(true)
    }
}

#Preview {
    List {
        HStack {
            Text("Navigable row")
            Spacer()
            DisclosureChevron()
        }
    }
}
