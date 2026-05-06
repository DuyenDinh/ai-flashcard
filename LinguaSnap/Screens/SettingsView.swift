import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [Flashcard]

    @State private var apiKeyInput   = ""
    @State private var isKeyVisible  = false
    @State private var keySaved      = false
    @State private var showResetAlert = false

    @AppStorage("targetCEFR") private var targetCEFR: String = CEFRLevel.b1.rawValue
    @AppStorage("dailyGoal")  private var dailyGoal: Int     = 20

    private var hasKey: Bool { Keychain.load() != nil }

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                learningSection
                statsSection
                dangerSection
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            if let saved = Keychain.load() {
                apiKeyInput = saved
            }
        }
    }

    // MARK: Sections

    private var apiKeySection: some View {
        Section {
            HStack {
                Group {
                    if isKeyVisible {
                        TextField("sk-ant-…", text: $apiKeyInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("sk-ant-…", text: $apiKeyInput)
                    }
                }
                .font(.system(.body, design: .monospaced))

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }

                if hasKey {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }

            HStack {
                Button("Save Key") {
                    Keychain.save(apiKey: apiKeyInput.trimmingCharacters(in: .whitespaces))
                    withAnimation { keySaved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if keySaved {
                    Text("Saved!").foregroundStyle(.green).transition(.opacity)
                }
            }

            Button("Remove Key", role: .destructive) {
                Keychain.delete()
                apiKeyInput = ""
            }
            .disabled(!hasKey)

        } header: {
            Text("Anthropic API Key")
        } footer: {
            Text("Your key is stored securely in the iOS Keychain and never leaves your device.")
        }
    }

    private var learningSection: some View {
        Section("Learning Preferences") {
            Picker("Target CEFR Level", selection: $targetCEFR) {
                ForEach(CEFRLevel.allCases, id: \.rawValue) { level in
                    Text("\(level.rawValue) — \(level.description)").tag(level.rawValue)
                }
            }

            Stepper("Daily Goal: \(dailyGoal) cards", value: $dailyGoal, in: 5...100, step: 5)
        }
    }

    private var statsSection: some View {
        Section("Statistics") {
            LabeledContent("Total Cards", value: "\(allCards.count)")
            LabeledContent("Due Today", value: "\(SRSEngine.dueCount(in: allCards))")
            LabeledContent("Mastered (≥5 reps)", value: "\(allCards.filter { $0.repetitions >= 5 }.count)")
            LabeledContent("Review Streak",
                           value: "\(UserDefaults(suiteName: SharedDataManager.appGroupID)?.integer(forKey: "review_streak") ?? 0) days")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Reset All Cards", role: .destructive) {
                showResetAlert = true
            }
        } header: {
            Text("Danger Zone")
        }
        .alert("Reset All Cards?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { deleteAllCards() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(allCards.count) flashcards and cannot be undone.")
        }
    }

    private func deleteAllCards() {
        allCards.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}

#Preview {
    SettingsView()
        .modelContainer(SharedDataManager.sharedModelContainer)
}
