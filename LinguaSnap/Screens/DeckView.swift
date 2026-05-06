import SwiftUI
import SwiftData

struct DeckView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flashcard.createdAt, order: .reverse) private var allCards: [Flashcard]

    @State private var searchText     = ""
    @State private var selectedCEFR: CEFRLevel? = nil
    @State private var cardToDelete: Flashcard? = nil
    @State private var showDeleteAlert = false

    private var filteredCards: [Flashcard] {
        allCards.filter { card in
            let matchesSearch = searchText.isEmpty
                || card.swedish.localizedCaseInsensitiveContains(searchText)
                || card.english.localizedCaseInsensitiveContains(searchText)
            let matchesCEFR = selectedCEFR == nil || card.cefr == selectedCEFR?.rawValue
            return matchesSearch && matchesCEFR
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cefrFilter
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if filteredCards.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Deck (\(allCards.count))")
            .searchable(text: $searchText, prompt: "Search Swedish or English…")
            .alert("Delete Card?", isPresented: $showDeleteAlert, presenting: cardToDelete) { card in
                Button("Delete", role: .destructive) { delete(card) }
                Button("Cancel", role: .cancel) {}
            } message: { card in
                Text("'\(card.swedish)' will be permanently removed.")
            }
        }
    }

    // MARK: Sub-views

    private var cefrFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedCEFR == nil) {
                    selectedCEFR = nil
                }
                ForEach(CEFRLevel.allCases, id: \.self) { level in
                    FilterChip(label: level.rawValue, isSelected: selectedCEFR == level) {
                        selectedCEFR = (selectedCEFR == level) ? nil : level
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var cardList: some View {
        List {
            ForEach(filteredCards) { card in
                DeckRow(card: card)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            cardToDelete = card
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No flashcards yet" : "No results found")
                .font(.title3.bold())
            Text(searchText.isEmpty
                 ? "Use the Scan tab or Share Extension to add Swedish words."
                 : "Try a different search term or CEFR filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: Helpers

    private func delete(_ card: Flashcard) {
        modelContext.delete(card)
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

struct DeckRow: View {
    let card: Flashcard

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.swedish)
                    .font(.headline)
                Text(card.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(card.cefr)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(cefrColor(card.cefrLevel), in: Capsule())

                if card.isDueToday {
                    Text("Due")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text(nextReviewLabel(card.nextReviewDate))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func nextReviewLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 0 { return "Due now" }
        if days == 1 { return "Tomorrow" }
        return "In \(days)d"
    }

    private func cefrColor(_ level: CEFRLevel) -> Color {
        switch level {
        case .a1: return .green
        case .a2: return .mint
        case .b1: return .blue
        case .b2: return .indigo
        case .c1: return .orange
        case .c2: return .red
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.indigo
                        : Color(.secondarySystemGroupedBackground)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : Color(.separator),
                        lineWidth: 1
                    )
                )
        }
    }
}

#Preview {
    DeckView()
        .modelContainer(SharedDataManager.sharedModelContainer)
}
