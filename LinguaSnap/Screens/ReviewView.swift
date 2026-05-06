import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let cards: [Flashcard]

    @State private var currentIndex = 0
    @State private var isFlipped     = false
    @State private var sessionDone   = false
    @State private var reviewedCount = 0
    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1

    private var currentCard: Flashcard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var body: some View {
        Group {
            if sessionDone || currentCard == nil {
                sessionCompleteView
            } else {
                reviewSessionView
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End Session") { dismiss() }
            }
        }
    }

    // MARK: Session View

    private var reviewSessionView: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            if let card = currentCard {
                flashCard(card: card)
                    .offset(x: cardOffset)
                    .opacity(cardOpacity)
                    .onTapGesture { withAnimation(.spring()) { isFlipped.toggle() } }
            }

            Spacer()

            if isFlipped {
                ratingButtons
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding()
            } else {
                tapHint
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(currentIndex + 1) / \(cards.count)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.indigo)
                    .frame(
                        width: geo.size.width * CGFloat(currentIndex) / CGFloat(max(cards.count, 1)),
                        height: 6
                    )
                    .animation(.easeInOut, value: currentIndex)
            }
        }
        .frame(height: 6)
    }

    private func flashCard(card: Flashcard) -> some View {
        ZStack {
            // Back
            CardFace(card: card, isFront: false)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -90), axis: (1, 0, 0))
                .opacity(isFlipped ? 1 : 0)

            // Front
            CardFace(card: card, isFront: true)
                .rotation3DEffect(.degrees(isFlipped ? 90 : 0), axis: (1, 0, 0))
                .opacity(isFlipped ? 0 : 1)
        }
        .animation(.spring(duration: 0.45), value: isFlipped)
        .padding(.horizontal, 20)
    }

    private var tapHint: some View {
        Text("Tap card to reveal answer")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var ratingButtons: some View {
        VStack(spacing: 10) {
            Text("How well did you recall this?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(RecallRating.allCases, id: \.self) { rating in
                    RatingButton(rating: rating) {
                        applyRating(rating)
                    }
                }
            }
        }
    }

    // MARK: Session Complete

    private var sessionCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)

            Text("Session Complete!")
                .font(.largeTitle.bold())

            Text("You reviewed \(reviewedCount) card\(reviewedCount == 1 ? "" : "s").")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Done") {
                updateStreak()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
        }
        .padding()
    }

    // MARK: Logic

    private func applyRating(_ rating: RecallRating) {
        guard let card = currentCard else { return }
        SRSEngine.review(card, rating: rating)
        try? modelContext.save()
        reviewedCount += 1
        advanceCard()
    }

    private func advanceCard() {
        withAnimation(.easeIn(duration: 0.2)) {
            cardOffset  = -UIScreen.main.bounds.width
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isFlipped = false
            if currentIndex + 1 >= cards.count {
                sessionDone = true
            } else {
                currentIndex += 1
            }
            cardOffset  = UIScreen.main.bounds.width
            cardOpacity = 0
            withAnimation(.easeOut(duration: 0.2)) {
                cardOffset  = 0
                cardOpacity = 1
            }
        }
    }

    private func updateStreak() {
        let defaults = UserDefaults(suiteName: SharedDataManager.appGroupID)
        let today = Calendar.current.startOfDay(for: Date())
        let lastKey = "last_review_day"
        let streakKey = "review_streak"

        if let last = defaults?.object(forKey: lastKey) as? Date {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            if Calendar.current.isDate(last, inSameDayAs: yesterday) {
                let current = defaults?.integer(forKey: streakKey) ?? 0
                defaults?.set(current + 1, forKey: streakKey)
            } else if !Calendar.current.isDate(last, inSameDayAs: today) {
                defaults?.set(1, forKey: streakKey)
            }
        } else {
            defaults?.set(1, forKey: streakKey)
        }
        defaults?.set(today, forKey: lastKey)
    }
}

// MARK: - Card Face View

struct CardFace: View {
    let card: Flashcard
    let isFront: Bool

    var body: some View {
        VStack(spacing: 16) {
            // CEFR badge
            Text(card.cefr)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(cefrColor(card.cefrLevel), in: Capsule())

            Spacer()

            if isFront {
                frontContent
            } else {
                backContent
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 340)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 8)
        )
    }

    private var frontContent: some View {
        VStack(spacing: 12) {
            Text(card.swedish)
                .font(.system(size: 48, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)

            if !card.sourceContext.isEmpty {
                Text(""\(card.sourceContext)"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .italic()
                    .lineLimit(3)
            }
        }
    }

    private var backContent: some View {
        VStack(spacing: 16) {
            Text(card.english)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if !card.exampleSentenceSV.isEmpty {
                Divider()
                VStack(spacing: 6) {
                    Text(card.exampleSentenceSV)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(card.exampleSentenceEN)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
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

// MARK: - Rating Button

struct RatingButton: View {
    let rating: RecallRating
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: rating.systemImage)
                    .font(.title2)
                Text(rating.label)
                    .font(.caption2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(ratingColor)
            .background(ratingColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var ratingColor: Color {
        switch rating {
        case .again: return .red
        case .hard:  return .orange
        case .good:  return .green
        case .easy:  return .blue
        }
    }
}

#Preview {
    NavigationStack {
        ReviewView(cards: [
            Flashcard(
                swedish: "kärlek",
                english: "love",
                cefr: "A1",
                exampleSentenceSV: "Jag har kärlek till dig.",
                exampleSentenceEN: "I have love for you.",
                sourceContext: "…en roman om kärlek…"
            )
        ])
    }
    .modelContainer(SharedDataManager.sharedModelContainer)
}
