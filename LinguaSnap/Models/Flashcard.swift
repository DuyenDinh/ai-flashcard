import Foundation
import SwiftData

@Model
final class Flashcard {
    var id: UUID
    var swedish: String
    var english: String
    var cefr: String
    var exampleSentenceSV: String
    var exampleSentenceEN: String
    var sourceContext: String
    var createdAt: Date

    // SM-2 SRS fields
    var interval: Int        // days until next review
    var repetitions: Int     // number of successful reviews in a row
    var easeFactor: Double   // starts at 2.5, min 1.3
    var nextReviewDate: Date

    init(
        swedish: String,
        english: String,
        cefr: String,
        exampleSentenceSV: String = "",
        exampleSentenceEN: String = "",
        sourceContext: String = ""
    ) {
        self.id = UUID()
        self.swedish = swedish
        self.english = english
        self.cefr = cefr
        self.exampleSentenceSV = exampleSentenceSV
        self.exampleSentenceEN = exampleSentenceEN
        self.sourceContext = sourceContext
        self.createdAt = Date()
        // SRS defaults
        self.interval = 1
        self.repetitions = 0
        self.easeFactor = 2.5
        self.nextReviewDate = Date()
    }

    var isDueToday: Bool {
        nextReviewDate <= Date()
    }

    var cefrLevel: CEFRLevel {
        CEFRLevel(rawValue: cefr) ?? .a1
    }
}

enum CEFRLevel: String, CaseIterable, Codable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var color: String {
        switch self {
        case .a1: return "green"
        case .a2: return "mint"
        case .b1: return "blue"
        case .b2: return "indigo"
        case .c1: return "orange"
        case .c2: return "red"
        }
    }

    var description: String {
        switch self {
        case .a1: return "Beginner"
        case .a2: return "Elementary"
        case .b1: return "Intermediate"
        case .b2: return "Upper-Intermediate"
        case .c1: return "Advanced"
        case .c2: return "Mastery"
        }
    }
}
