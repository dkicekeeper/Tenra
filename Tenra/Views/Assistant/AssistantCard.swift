//
//  AssistantCard.swift
//  Tenra
//
//  A card of the assistant's reply under an optional title: a chart, payments, a draft, an
//  attachment. DesignKit's `FormSection` (8.6.0, the one rhythm of every card): the title 12 pt
//  above the card, a divider between its pieces, under each row's text. Every piece pads itself
//  12 pt above and below: the rows do, a chart, a status line or a button takes
//  `.padding(.vertical, AppSpacing.md)` at its call site.
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
        FormSection(header: title) {
            content
        }
    }
}
