import SwiftUI
import SwiftData

@main
struct AIFlashcardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SharedDataManager.sharedModelContainer)
    }
}
