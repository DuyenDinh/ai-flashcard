import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [Flashcard]

    @State private var navigateToReview = false
    @State private var showStreakInfo    = false

    private var dueCards: [Flashcard] { SRSEngine.dueCards(from: allCards) }
    private var dueCount: Int { dueCards.count }
    private var totalCards: Int { allCards.count }
    private var masteredCards: Int { allCards.filter { $0.repetitions >= 5 }.count }

    // Simple streak: days in a row where at least one review was done.
    // Tracked via UserDefaults for simplicity.
    private var streak: Int {
        UserDefaults(suiteName: SharedDataManager.appGroupID)?
            .integer(forKey: "review_streak") ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerCard
                    statsRow
                    reviewButton
                    cefrBreakdown
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI Flashcard")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $navigateToReview) {
                ReviewView(cards: dueCards)
            }
        }
    }

    // MARK: Sub-views

    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .indigo.opacity(0.4), radius: 12, x: 0, y: 6)

            VStack(spacing: 8) {
                Text("🇸🇪 Swedish → English")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                Text("\(dueCount)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(dueCount == 1 ? "card due today" : "cards due today")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.vertical, 32)

            // Streak badge
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showStreakInfo = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("🔥")
                            Text("\(streak)")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                    }
                }
                Spacer()
            }
            .padding()
        }
        .alert("Review Streak", isPresented: $showStreakInfo) {
            Button("OK") {}
        } message: {
            Text("You've reviewed cards \(streak) day\(streak == 1 ? "" : "s") in a row. Keep it up!")
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(title: "Total", value: "\(totalCards)", icon: "rectangle.stack", color: .blue)
            StatCard(title: "Mastered", value: "\(masteredCards)", icon: "star.fill", color: .orange)
            StatCard(title: "Due", value: "\(dueCount)", icon: "clock.fill", color: .red)
        }
    }

    private var reviewButton: some View {
        Button {
            if dueCount > 0 { navigateToReview = true }
        } label: {
            HStack {
                Image(systemName: dueCount > 0 ? "play.fill" : "checkmark.seal.fill")
                Text(dueCount > 0 ? "Start Review (\(dueCount))" : "All caught up!")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(dueCount > 0 ? Color.indigo : Color.green)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: (dueCount > 0 ? Color.indigo : Color.green).opacity(0.35),
                    radius: 8, x: 0, y: 4)
        }
        .disabled(dueCount == 0)
    }

    private var cefrBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By CEFR Level")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(CEFRLevel.allCases, id: \.self) { level in
                let count = allCards.filter { $0.cefr == level.rawValue }.count
                if count > 0 {
                    CEFRRow(level: level, count: count, total: max(totalCards, 1))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CEFRRow: View {
    let level: CEFRLevel
    let count: Int
    let total: Int

    var body: some View {
        HStack {
            Text(level.rawValue)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 32, height: 20)
                .background(cefrColor, in: RoundedRectangle(cornerRadius: 6))

            Text(level.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(count)")
                .font(.subheadline.bold())

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cefrColor)
                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(total), height: 6)
                }
            }
            .frame(width: 80, height: 6)
        }
    }

    private var cefrColor: Color {
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

#Preview {
    HomeView()
        .modelContainer(SharedDataManager.sharedModelContainer)
}
