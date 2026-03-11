//
//  EditSheetContainer.swift
//  AIFinanceManager
//
//  Generic wrapper for modal edit-form sheets.
//  Extracts the repeated NavigationView → Form → toolbar(xmark / checkmark) shell
//  that was duplicated across AccountEditView, CategoryEditView, SubcategoryEditView,
//  DepositEditView, and SubscriptionEditView.
//

import SwiftUI

/// A reusable container that wraps Form content inside a NavigationView
/// with the standard modal edit-sheet chrome: title, cancel (xmark) and save (checkmark) toolbar buttons.
///
/// Usage:
/// ```swift
/// EditSheetContainer(
///     title: account == nil ? "New Account" : "Edit Account",
///     isSaveDisabled: name.isEmpty,
///     onSave: { /* save logic */ },
///     onCancel: onCancel
/// ) {
///     Section(header: Text("Name")) { ... }
///     Section(header: Text("Balance")) { ... }
/// }
/// ```
struct EditSheetContainer<Content: View>: View {
    /// Navigation title displayed at the top of the sheet
    let title: String
    /// When `true`, the save (checkmark) button is disabled
    let isSaveDisabled: Bool
    /// When `true` (default), content is wrapped in `Form {}`.
    /// Pass `false` for hero-style views that supply their own `ScrollView`.
    let wrapInForm: Bool
    /// Called when the user taps the checkmark button
    let onSave: () -> Void
    /// Called when the user taps the xmark button
    let onCancel: () -> Void
    /// The Form sections content provided by the caller
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        isSaveDisabled: Bool,
        wrapInForm: Bool = true,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isSaveDisabled = isSaveDisabled
        self.wrapInForm = wrapInForm
        self.onSave = onSave
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        NavigationStack {
            if wrapInForm {
                Form {
                    content()
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
            } else {
                content()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        toolbarContent
                    }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                HapticManager.light()
                onSave()
            } label: {
                Image(systemName: "checkmark")
            }
            .disabled(isSaveDisabled)
        }
    }
}

// MARK: - Previews

#Preview("Form variant") {
    EditSheetContainer(
        title: "Edit Account",
        isSaveDisabled: false,
        onSave: {},
        onCancel: {}
    ) {
        Section("Name") {
            TextField("Account name", text: .constant("Kaspi Gold"))
        }
        Section("Balance") {
            TextField("Initial balance", text: .constant("150 000"))
        }
    }
}

#Preview("Save disabled") {
    EditSheetContainer(
        title: "New Category",
        isSaveDisabled: true,
        onSave: {},
        onCancel: {}
    ) {
        Section("Name") {
            TextField("Category name", text: .constant(""))
        }
    }
}
