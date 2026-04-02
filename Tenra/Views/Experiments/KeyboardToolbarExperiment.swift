import SwiftUI

struct KeyboardToolbarExperiment: View {
    @State private var text = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            TextField("Введите текст...", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .padding(.horizontal)
                
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {

                        Button {
                            // action
                        } label: {
                            Text("Продолжить")
                                .fontWeight(.semibold)
                                .foregroundStyle(.black)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.glassProminent)
                        .tint(.yellow)

                        Spacer()

                        Button("Готово") {
                            isTextFieldFocused = false
                        }
                    }
                }

            Spacer()

            if !isTextFieldFocused {
                Button {
                    // action
                } label: {
                    Text("Продолжить")
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTextFieldFocused)
        .navigationTitle("Эксперимент")
    }
}

#Preview {
    NavigationStack {
        KeyboardToolbarExperiment()
    }
}
