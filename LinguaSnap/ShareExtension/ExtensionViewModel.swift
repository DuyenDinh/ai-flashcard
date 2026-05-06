import Foundation
import SwiftData

/// ViewModel shared by ShareViewController.
/// Handles all API calls and state transitions for the Share Extension UI.
@MainActor
final class ExtensionViewModel: ObservableObject {

    enum Mode { case idle, singleWord, batch }
    enum State { case idle, loading, wordReady(WordTranslation), batchReady([BatchWord]), error(String) }

    @Published var state: State = .idle
    @Published var inputText: String = ""
    @Published var batchWords: [BatchWord] = []
    @Published var mode: Mode = .idle

    // MARK: Single word translation

    func translateWord(_ word: String) async {
        state = .loading
        do {
            let result = try await LinguaService.shared.translate(word: word)
            state = .wordReady(result)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: Batch extraction

    func extractBatch(from text: String, maxCEFR: CEFRLevel) async {
        state = .loading
        do {
            var words = try await LinguaService.shared.extractVocabulary(from: text, maxCEFR: maxCEFR)
            for i in words.indices { words[i].isSelected = true }
            batchWords = words
            state = .batchReady(words)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: Save to shared store

    func saveSelected() throws {
        let selected = batchWords.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        let container = SharedDataManager.sharedModelContainer
        let context   = ModelContext(container)

        for w in selected {
            let card = Flashcard(swedish: w.swedish, english: w.english, cefr: w.cefr)
            context.insert(card)
        }
        try context.save()
    }

    func saveSingleWord(_ translation: WordTranslation) throws {
        let container = SharedDataManager.sharedModelContainer
        let context   = ModelContext(container)
        let card = Flashcard(
            swedish: translation.swedish,
            english: translation.english,
            cefr: translation.cefr,
            exampleSentenceSV: translation.exampleSentenceSV,
            exampleSentenceEN: translation.exampleSentenceEN
        )
        context.insert(card)
        try context.save()
    }
}
