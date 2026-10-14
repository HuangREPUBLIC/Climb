import SwiftUI
import SwiftData

/// Where the two API keys are pasted. Opened from the account sheet, and on
/// its own when Riot rejects the key — a personal key lasts 24 hours.
struct APIKeysView: View {
    /// Why the screen opened by itself, if it did.
    var reason: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var riotKey = APIKeys.riot
    @State private var geminiKey = APIKeys.gemini

    var body: some View {
        Form {
            if let reason {
                Section {
                    // Orange text on white was hard to read; only the icon is orange.
                    Label {
                        Text(reason)
                    } icon: {
                        Image(systemName: "key.slash").foregroundStyle(Theme.orange)
                    }
                }
            }

            Section {
                keyField("RGAPI-…", text: $riotKey)
                Link("Get today's key at developer.riotgames.com", destination: URL(string: "https://developer.riotgames.com")!)
            } header: {
                Text("Riot API key")
            } footer: {
                Text("Personal keys expire every 24 hours.")
            }

            Section {
                keyField("AIza…", text: $geminiKey)
            } header: {
                Text("Gemini API key")
            } footer: {
                Text("Free from aistudio.google.com/apikey. Used by the AI coach.")
            }
        }
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Pushed from the account sheet it already has a back button;
            // only the standalone expiry prompt needs its own way out.
            if reason != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(riotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// Paste is the whole workflow, so it's one tap beside the field.
    private func keyField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { text.wrappedValue = pasted }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
        }
    }

    private func save() {
        let newRiotKey = riotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let riotKeyChanged = newRiotKey != APIKeys.riot
        APIKeys.riot = newRiotKey
        APIKeys.gemini = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        APIKeyPrompt.shared.riotKeyRejected = false
        if riotKeyChanged {
            // A new key is the moment syncing works again.
            let context = modelContext
            Task { try? await MatchImportService.syncLinkedAccount(context: context) }
        }
        dismiss()
    }
}
