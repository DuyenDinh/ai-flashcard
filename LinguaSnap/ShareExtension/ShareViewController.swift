import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Share Extension.
/// Wraps a SwiftUI view in a UIHostingController.
final class ShareViewController: UIViewController {

    private let viewModel = ExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedContent()
    }

    // MARK: Extract shared content from the extension context

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            showShareUI(initialText: "")
            return
        }

        for item in items {
            for provider in (item.attachments ?? []) {
                // Prefer plain text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            let text = (data as? String) ?? ""
                            self?.showShareUI(initialText: text)
                        }
                    }
                    return
                }
                // Fallback: URL → use the URL string as the text to scan
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            let urlString = (data as? URL)?.absoluteString ?? ""
                            self?.showShareUI(initialText: urlString)
                        }
                    }
                    return
                }
            }
        }
        showShareUI(initialText: "")
    }

    private func showShareUI(initialText: String) {
        viewModel.inputText = initialText

        let shareView = ShareExtensionView(viewModel: viewModel) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        } onCancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "AIFlashcard", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Cancelled by user"]
            ))
        }

        let host = UIHostingController(rootView: shareView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    @ObservedObject var viewModel: ExtensionViewModel
    let onDone: () -> Void
    let onCancel: () -> Void

    @AppStorage("targetCEFR") private var targetCEFR: String = CEFRLevel.b1.rawValue

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    idleModeView
                case .loading:
                    ProgressView("Thinking…")
                        .padding()
                case .wordReady(let translation):
                    WordPreviewView(translation: translation) {
                        try? viewModel.saveSingleWord(translation)
                        onDone()
                    } onCancel: { onCancel() }
                case .batchReady:
                    batchSelectionView
                case .error(let msg):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(msg).multilineTextAlignment(.center)
                        Button("Try Again") { viewModel.state = .idle }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Flashcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    // MARK: Idle – choose mode

    private var idleModeView: some View {
        VStack(spacing: 20) {
            Text("What would you like to do?")
                .font(.headline)

            if !viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                // Single-word: use first word only
                let firstWord = viewModel.inputText
                    .components(separatedBy: .whitespacesAndNewlines)
                    .first ?? viewModel.inputText

                Button {
                    Task { await viewModel.translateWord(firstWord) }
                } label: {
                    ModeButton(
                        icon: "character.book.closed.fill",
                        title: "Translate word",
                        subtitle: ""\(firstWord)""
                    )
                }

                Button {
                    let level = CEFRLevel(rawValue: targetCEFR) ?? .b1
                    Task { await viewModel.extractBatch(from: viewModel.inputText, maxCEFR: level) }
                } label: {
                    ModeButton(
                        icon: "list.bullet.rectangle.portrait.fill",
                        title: "Batch scan",
                        subtitle: "Extract up to \(targetCEFR) vocabulary from entire text"
                    )
                }
            } else {
                Text("No text was shared. Please select text in another app and share it to AI Flashcard.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .padding()
    }

    // MARK: Batch selection

    private var batchSelectionView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.batchWords.indices, id: \.self) { i in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(viewModel.batchWords[i].swedish).font(.headline)
                            Text(viewModel.batchWords[i].english).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(viewModel.batchWords[i].cefr)
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.indigo.opacity(0.15), in: Capsule())
                        Image(systemName: viewModel.batchWords[i].isSelected
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.batchWords[i].isSelected ? .indigo : .secondary)
                            .onTapGesture { viewModel.batchWords[i].isSelected.toggle() }
                    }
                }
            }

            Button {
                try? viewModel.saveSelected()
                onDone()
            } label: {
                Text("Add \(viewModel.batchWords.filter(\.isSelected).count) cards to Deck")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.batchWords.filter(\.isSelected).isEmpty)
            .padding()
        }
        .navigationTitle("\(viewModel.batchWords.filter(\.isSelected).count) Selected")
    }
}

// MARK: - Word Preview

struct WordPreviewView: View {
    let translation: WordTranslation
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(translation.swedish)
                .font(.system(size: 48, weight: .bold, design: .serif))

            Text(translation.english)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(translation.cefr)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.indigo.opacity(0.15), in: Capsule())

            if !translation.exampleSentenceSV.isEmpty {
                Divider()
                VStack(spacing: 6) {
                    Text(translation.exampleSentenceSV).italic()
                    Text(translation.exampleSentenceEN).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Add to Deck", action: onSave)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)

            Button("Cancel", action: onCancel)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Mode Button

struct ModeButton: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
