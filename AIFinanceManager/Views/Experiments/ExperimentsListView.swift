import SwiftUI

struct ExperimentsListView: View {
    var body: some View {
        List {
            NavigationLink {
                KeyboardToolbarExperiment()
            } label: {
                Label("Keyboard Toolbar", systemImage: "keyboard")
            }
        }
        .navigationTitle("Эксперименты")
    }
}

#Preview {
    NavigationStack {
        ExperimentsListView()
    }
}
