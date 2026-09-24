import SwiftUI

struct ExperimentsListView: View {

    @State private var snapshot = IntentUsageCounters.shared.snapshot()
    #if DEBUG
    @State private var walletProbeEntries: [WalletPaymentProbeEntry] = []
    #endif

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

            #if DEBUG
            // Wallet automation spike (plans/004-spike-wallet-automation.md):
            // raw payloads the Shortcuts "Wallet" automation passed to the probe.
            Section("Wallet probe (local only)") {
                if walletProbeEntries.isEmpty {
                    Text("No payments recorded yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(walletProbeEntries) { entry in
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(entry.receivedAt.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("merchant: \(entry.merchant ?? "nil")")
                        Text("amount text: \(entry.rawAmount ?? "nil")")
                        Text("amount: \(entry.currencyAmountValue.map { String($0) } ?? "nil") \(entry.currencyAmountCode ?? "")")
                        Text("card: \(entry.card ?? "nil"), name: \(entry.name ?? "nil")")
                        Text("background: \(entry.ranInBackground ? "yes" : "no"), history: \(entry.historyCount)")
                        Text("suggested: \(entry.suggestedCategory ?? "nil")")
                    }
                    .font(.caption)
                    .textSelection(.enabled)
                }
                Button("Clear probe log", role: .destructive) {
                    WalletPaymentProbeLog.shared.clear()
                    walletProbeEntries = []
                }
            }
            #endif
        }
        .navigationTitle("Эксперименты")
        .onAppear {
            snapshot = IntentUsageCounters.shared.snapshot()
            #if DEBUG
            walletProbeEntries = WalletPaymentProbeLog.shared.entries()
            #endif
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentsListView()
    }
}
