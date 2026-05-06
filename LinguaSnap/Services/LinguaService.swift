import Foundation
import Security

// MARK: - Response Models

struct WordTranslation: Codable {
    let swedish: String
    let english: String
    let cefr: String
    let exampleSentenceSV: String
    let exampleSentenceEN: String

    enum CodingKeys: String, CodingKey {
        case swedish, english, cefr
        case exampleSentenceSV = "example_sentence_sv"
        case exampleSentenceEN = "example_sentence_en"
    }
}

struct BatchWord: Codable, Identifiable {
    var id: UUID = UUID()
    let swedish: String
    let english: String
    let cefr: String
    var isSelected: Bool = true

    enum CodingKeys: String, CodingKey {
        case swedish, english, cefr
    }
}

// MARK: - Errors

enum LinguaError: LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case decodingError(String)
    case rateLimited
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key found. Please add your Anthropic API key in Settings."
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .decodingError(let detail):
            return "Failed to parse response: \(detail)"
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        }
    }
}

// MARK: - Keychain Helper

enum Keychain {
    private static let service = "com.yourname.linguasnap"
    private static let account = "anthropic_api_key"

    static func save(apiKey: String) {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecValueData as String:        data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - LinguaService

actor LinguaService {
    static let shared = LinguaService()

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model   = "claude-sonnet-4-20250514"
    private let version = "2023-06-01"

    private init() {}

    // MARK: Single word translation

    /// Translates a single Swedish word to English and returns a `WordTranslation`.
    func translate(word: String) async throws -> WordTranslation {
        let prompt = """
        Translate the Swedish word '\(word)' to English. Also classify its CEFR level.
        Return ONLY valid JSON (no markdown, no explanation):
        {
          "swedish": "...",
          "english": "...",
          "cefr": "A1|A2|B1|B2|C1|C2",
          "example_sentence_sv": "...",
          "example_sentence_en": "..."
        }
        """
        let raw = try await callClaude(prompt: prompt)
        return try decode(WordTranslation.self, from: raw)
    }

    // MARK: Batch CEFR vocabulary extraction

    /// Extracts Swedish vocabulary from `text` up to and including `cefrLevel`.
    func extractVocabulary(from text: String, maxCEFR: CEFRLevel) async throws -> [BatchWord] {
        let prompt = """
        You are a Swedish language teacher. Extract all unique Swedish words from the text below \
        that are at CEFR level \(maxCEFR.rawValue) or below. \
        Ignore proper nouns, numbers, and punctuation. \
        Return ONLY a valid JSON array (no markdown, no explanation):
        [{ "swedish": "...", "english": "...", "cefr": "A1|A2|B1|B2|C1|C2" }]

        Text:
        \(text)
        """
        let raw = try await callClaude(prompt: prompt)
        return try decode([BatchWord].self, from: raw)
    }

    // MARK: Private helpers

    private func callClaude(prompt: String) async throws -> String {
        guard let apiKey = Keychain.load(), !apiKey.isEmpty else {
            throw LinguaError.missingAPIKey
        }

        guard let url = URL(string: baseURL) else {
            throw LinguaError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                forHTTPHeaderField: "x-api-key")
        request.setValue(version,               forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LinguaError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LinguaError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            break
        case 429:
            throw LinguaError.rateLimited
        default:
            throw LinguaError.serverError(http.statusCode)
        }

        // Parse Anthropic response envelope
        struct AnthropicResponse: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }
        let envelope = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = envelope.content.first?.text else {
            throw LinguaError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        // Strip potential markdown fences
        var json = raw
        if json.hasPrefix("```") {
            let lines = json.components(separatedBy: "\n")
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = json.data(using: .utf8) else {
            throw LinguaError.decodingError("Could not convert response to data")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LinguaError.decodingError(error.localizedDescription)
        }
    }
}
