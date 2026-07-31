import SwiftUI

struct ExperimentsListView: View {

    @State private var snapshot = IntentUsageCounters.shared.snapshot()

    var body: some View {
        List {
            NavigationLink {
                KeyboardToolbarExperiment()
            } label: {
                Label("Keyboard Toolbar", systemImage: "keyboard")
            }

            // Developer-only screen (the navigation title above is already
            // hardcoded Russian), so these strings stay unlocalized to match.
            //
            // The ratio to watch is fallbacks vs intent adds: a rising share of
            // fallbacks means real phrases are failing to resolve.
            Section("Intent usage (local only)") {
                LabeledContent("Added via intents", value: "\(snapshot.intentAdds)")
                LabeledContent("Added manually", value: "\(snapshot.manualAdds)")
                LabeledContent("Fell back to app", value: "\(snapshot.fallbacks)")
                Button("Reset counters") {
                    IntentUsageCounters.shared.reset()
                    snapshot = IntentUsageCounters.shared.snapshot()
                }
            }
        }
        .navigationTitle("Эксперименты")
        .onAppear { snapshot = IntentUsageCounters.shared.snapshot() }
    }
}

#Preview {
    NavigationStack {
        ExperimentsListView()
    }
}
