//
//  AssistantMemoryView.swift
//  Tenra
//
//  "What Ten knows about me" (docs/plan-ai-assistant.md §3.4), from Settings → Assistant: the
//  facts the assistant remembers (AgentMemory), oldest first. A tap opens one to change it, a
//  swipe forgets it, "+" adds one by hand, "Forget everything" clears the list. Ten sees them
//  in every chat; facts it proposes in a chat arrive here once the person saves them.
//

import SwiftUI

struct AssistantMemoryView: View {
    let memory: AgentMemory

    /// A fact open in the editor; none for a new one.
    private struct Editing: Identifiable {
        let fact: AgentFact?
        var id: String { fact?.id ?? "new" }
    }

    @State private var editing: Editing?
    @State private var showingForgetAll = false

    var body: some View {
        Group {
            if !memory.isLoaded {
                // The rows to come (each fact is an ItemRow in the large style).
                List {
                    ForEach(0..<3, id: \.self) { _ in
                        ItemRowSkeleton(style: .large)
                    }
                }
                .transition(.opacity)
            } else if memory.facts.isEmpty {
                MascotEmptyState(
                    icon: "brain",
                    title: String(localized: "assistant.memory.emptyTitle"),
                    description: String(localized: "assistant.memory.emptyMessage"),
                    line: String(localized: "assistant.empty.memory")
                )
                .transition(.skeletonReveal)
            } else {
                List {
                    Section {
                        ForEach(memory.facts) { fact in
                            row(fact)
                        }
                    } footer: {
                        Text(String(localized: "assistant.memory.footer"))
                    }
                    Section {
                        ActionSettingsRow(
                            icon: "trash",
                            title: String(localized: "assistant.memory.forgetAll"),
                            isDestructive: true
                        ) {
                            showingForgetAll = true
                        }
                    }
                }
                .transition(.skeletonReveal)
            }
        }
        .animation(AppAnimation.smooth, value: memory.isLoaded)
        .navigationTitle(String(localized: "assistant.memory.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "assistant.memory.add"), systemImage: "plus") {
                    editing = Editing(fact: nil)
                }
                .disabled(!memory.isLoaded || memory.facts.count >= AgentMemory.limit)
            }
        }
        .sheet(item: $editing) { target in
            AssistantFactEditor(memory: memory, fact: target.fact)
        }
        .alert(String(localized: "assistant.memory.forgetAllTitle"), isPresented: $showingForgetAll) {
            Button(String(localized: "assistant.memory.forgetAll"), role: .destructive) {
                HapticManager.warning()
                Task { await memory.forgetAll() }
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "assistant.memory.forgetAllMessage"))
        }
        .task { await memory.load() }
    }

    private func row(_ fact: AgentFact) -> some View {
        Button {
            editing = Editing(fact: fact)
        } label: {
            ItemRow(
                fact.text,
                meta: [MetaLine([.text(Text(fact.updatedAt, format: .dateTime.day().month().year()))])],
                style: .large
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "assistant.memory.editHint"))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.warning()
                Task { await memory.forget(fact.id) }
            } label: {
                Label(String(localized: "assistant.memory.forget"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await memory.forget(fact.id) }
            } label: {
                Label(String(localized: "assistant.memory.forget"), systemImage: "trash")
            }
        }
    }
}

/// One fact to write or change: a short sentence, at most `AgentMemory.maxLength` characters.
struct AssistantFactEditor: View {
    let memory: AgentMemory
    /// The fact to change; none writes a new one.
    let fact: AgentFact?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?
    @State private var isSaving = false

    var body: some View {
        EditSheetContainer(
            title: fact == nil ? String(localized: "assistant.memory.new") : String(localized: "assistant.memory.edit"),
            isSaveDisabled: isEmpty || text.count > AgentMemory.maxLength,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                FormSection(footer: String(localized: "assistant.memory.editorFooter")) {
                    FormTextField(
                        text: $text,
                        placeholder: String(localized: "assistant.memory.placeholder"),
                        style: .rowMultiline(min: 2, max: 6),
                        errorMessage: problem,
                        limit: AgentMemory.maxLength,
                        autofocus: true
                    )
                }
                .padding(AppSpacing.lg)
            }
        }
        .onAppear { text = fact?.text ?? "" }
        .onChange(of: text) { problem = nil }
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        if let fact, fact.text == text {
            dismiss()
            return
        }
        isSaving = true
        Task {
            do {
                if let fact {
                    try await memory.change(fact.id, to: text)
                } else {
                    try await memory.remember(text)
                }
                HapticManager.success()
                dismiss()
            } catch let failure as AgentMemoryError {
                problem = Self.message(for: failure)
                isSaving = false
                HapticManager.error()
            } catch {
                isSaving = false
            }
        }
    }

    private static func message(for failure: AgentMemoryError) -> String {
        switch failure {
        case .empty, .tooLong: String(localized: "assistant.memory.tooLong")
        case .full: String(format: String(localized: "assistant.memory.full"), AgentMemory.limit)
        case .duplicate: String(localized: "assistant.memory.duplicate")
        case .unknown: String(localized: "assistant.memory.gone")
        }
    }
}

#Preview {
    NavigationStack {
        AssistantMemoryView(memory: AgentMemory(store: nil))
    }
}
