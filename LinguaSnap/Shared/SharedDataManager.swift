import Foundation
import SwiftData

/// Provides the shared SwiftData ModelContainer stored in the App Group container,
/// so both the main app and the Share Extension read/write the same database.
enum SharedDataManager {
    static let appGroupID = "group.com.yourname.linguasnap"

    static var sharedModelContainer: ModelContainer = {
        let schema = Schema([Flashcard.self])
        let storeURL = containerURL.appendingPathComponent("AIFlashcard.sqlite")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    private static var containerURL: URL {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            // Fallback for simulators / tests that haven't configured the entitlement
            return URL.applicationSupportDirectory
        }
        return url
    }
}
