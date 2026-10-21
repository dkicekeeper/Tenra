//
//  AssistantCard.swift
//  Tenra
//
//  A card of the assistant's reply under an optional title: a chart, payments, a draft, an
//  attachment. The look of DesignKit's `FormSection(style: .glass)` (5.0.0, `ListCard` in
//  4.14.0), which 8.0.0 folded into the one glass section with dividers: a reply's card holds
//  more than rows (a chart, a status line, a button), so it keeps its own padding on every side
//  and `sm` between its pieces, no dividers.
//

import SwiftUI

struct AssistantCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let title, !title.isEmpty {
                SectionHeader(title)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                content
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}
