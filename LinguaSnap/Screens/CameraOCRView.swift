import SwiftUI
import Vision
import PhotosUI
import SwiftData

struct CameraOCRView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var extractedText  = ""
    @State private var batchWords: [BatchWord] = []
    @State private var isProcessing   = false
    @State private var errorMessage: String? = nil
    @State private var showWordSheet   = false
    @State private var showCamera      = false
    @State private var savedCount      = 0
    @State private var showSavedBanner = false

    @AppStorage("targetCEFR") private var targetCEFR: String = CEFRLevel.b1.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    imageSourcePicker
                    if !extractedText.isEmpty {
                        extractedTextCard
                    }
                    if isProcessing {
                        ProgressView("Analysing with Claude…")
                            .padding()
                    }
                    if let err = errorMessage {
                        ErrorBanner(message: err)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scan Text")
            .sheet(isPresented: $showWordSheet) {
                WordSelectionSheet(words: $batchWords) { selected in
                    saveWords(selected)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraSheet { image in
                    showCamera = false
                    if let img = image { runOCR(on: img) }
                }
            }
            .overlay(alignment: .bottom) {
                if showSavedBanner {
                    Text("✓ \(savedCount) card\(savedCount == 1 ? "" : "s") added!")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green, in: Capsule())
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: showSavedBanner)
        }
    }

    // MARK: Sub-views

    private var imageSourcePicker: some View {
        VStack(spacing: 12) {
            Text("Import Swedish text to extract vocabulary")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    SourceButton(icon: "camera.fill", label: "Camera")
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    SourceButton(icon: "photo.on.rectangle", label: "Photo Library")
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task { await loadPhoto(item) }
                }
            }

            // Manual paste fallback
            VStack(alignment: .leading, spacing: 6) {
                Text("Or paste text:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $extractedText)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))

                Button("Extract Vocabulary") {
                    Task { await extractVocabulary() }
                }
                .disabled(extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var extractedTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Extracted Text", systemImage: "text.viewfinder")
                .font(.headline)
            Text(extractedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
            Button("Extract Vocabulary") {
                Task { await extractVocabulary() }
            }
            .disabled(isProcessing)
            .buttonStyle(.bordered)
            .tint(.indigo)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Logic

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        runOCR(on: uiImage)
    }

    private func runOCR(on image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        isProcessing  = true
        errorMessage  = nil

        let request = VNRecognizeTextRequest { req, err in
            DispatchQueue.main.async {
                if let err { errorMessage = err.localizedDescription; isProcessing = false; return }
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                extractedText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                isProcessing = false
                Task { await extractVocabulary() }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    private func extractVocabulary() async {
        guard !extractedText.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        do {
            let level = CEFRLevel(rawValue: targetCEFR) ?? .b1
            batchWords = try await LinguaService.shared.extractVocabulary(
                from: extractedText,
                maxCEFR: level
            )
            showWordSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    private func saveWords(_ words: [BatchWord]) {
        for w in words {
            let card = Flashcard(swedish: w.swedish, english: w.english, cefr: w.cefr)
            modelContext.insert(card)
        }
        try? modelContext.save()
        savedCount = words.count
        showSavedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showSavedBanner = false
        }
    }
}

// MARK: - Supporting Views

struct SourceButton: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.indigo)
            Text(label)
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.4)))
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Word Selection Sheet

struct WordSelectionSheet: View {
    @Binding var words: [BatchWord]
    @Environment(\.dismiss) private var dismiss
    let onSave: ([BatchWord]) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(words.indices, id: \.self) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(words[i].swedish).font(.headline)
                            Text(words[i].english).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(words[i].cefr)
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.indigo.opacity(0.15), in: Capsule())
                        Image(systemName: words[i].isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(words[i].isSelected ? .indigo : .secondary)
                            .onTapGesture { words[i].isSelected.toggle() }
                    }
                }
            }
            .navigationTitle("\(words.filter(\.isSelected).count) selected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Deck") {
                        onSave(words.filter(\.isSelected))
                        dismiss()
                    }
                    .disabled(words.filter(\.isSelected).isEmpty)
                }
            }
        }
    }
}

// MARK: - Camera Sheet (UIKit wrapper)

struct CameraSheet: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}

#Preview {
    CameraOCRView()
        .modelContainer(SharedDataManager.sharedModelContainer)
}
