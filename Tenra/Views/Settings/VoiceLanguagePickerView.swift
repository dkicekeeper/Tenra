//
//  VoiceLanguagePickerView.swift
//  Tenra
//
//  Settings → General → Voice language: the languages speech recognition offers, with "the
//  app's language" first. A List of DesignKit's CheckmarkRow (`.settings`, the list pads it);
//  a pick saves to VoiceRecognitionLanguage's key and goes back. System search when the list is
//  long (NavigationPickerMetrics.searchThreshold, as DesignKit's own picker list).
//

import SwiftUI

struct VoiceLanguagePickerView: View {
    @Binding var selection: String
    let options: [(label: String, value: String)]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var shown: [(label: String, value: String)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }
        return options.filter { $0.label.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            ForEach(shown, id: \.value) { option in
                CheckmarkRow(option.label, isSelected: option.value == selection) {
                    selection = option.value
                    HapticManager.selection()
                    dismiss()
                }
            }
        }
        .navigationTitle(String(localized: "settings.voiceLanguage"))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SearchWhenLong(isEnabled: options.count > NavigationPickerMetrics.searchThreshold, query: $query))
    }
}

private struct SearchWhenLong: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query)
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        VoiceLanguagePickerView(
            selection: .constant(""),
            options: [(label: "App language", value: ""), (label: "English", value: "en-US"), (label: "Русский", value: "ru-RU")]
        )
    }
}
