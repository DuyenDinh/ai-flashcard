import Foundation

/// SM-2 spaced repetition algorithm implementation.
/// Reference: https://www.supermemo.com/en/archives1990-2015/english/ol/sm2
enum RecallRating: Int, CaseIterable {
    case again = 0   // Complete blackout / wrong
    case hard  = 1   // Correct but with serious difficulty
    case good  = 3   // Correct with some difficulty
    case easy  = 5   // Perfect response

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard:  return "Hard"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    var systemImage: String {
        switch self {
        case .again: return "xmark.circle.fill"
        case .hard:  return "minus.circle.fill"
        case .good:  return "checkmark.circle.fill"
        case .easy:  return "star.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .again: return "red"
        case .hard:  return "orange"
        case .good:  return "green"
        case .easy:  return "blue"
        }
    }
}

enum SRSEngine {
    static let minEaseFactor: Double = 1.3

    /// Apply SM-2 to a flashcard given the user's recall rating.
    /// Mutates `interval`, `repetitions`, `easeFactor`, and `nextReviewDate`.
    static func review(_ card: Flashcard, rating: RecallRating) {
        let q = rating.rawValue

        // Update ease factor
        let newEF = card.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        card.easeFactor = max(minEaseFactor, newEF)

        if q < 3 {
            // Failed recall: reset repetitions and re-show soon
            card.repetitions = 0
            card.interval = 1
        } else {
            // Successful recall: advance schedule
            switch card.repetitions {
            case 0:
                card.interval = 1
            case 1:
                card.interval = 6
            default:
                card.interval = Int((Double(card.interval) * card.easeFactor).rounded())
            }
            card.repetitions += 1
        }

        card.nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: card.interval,
            to: Date()
        ) ?? Date()
    }

    /// Number of cards due for review today.
    static func dueCount(in cards: [Flashcard]) -> Int {
        cards.filter { $0.isDueToday }.count
    }

    /// Cards due today, sorted by overdue-ness (most overdue first).
    static func dueCards(from cards: [Flashcard]) -> [Flashcard] {
        cards
            .filter { $0.isDueToday }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
}
