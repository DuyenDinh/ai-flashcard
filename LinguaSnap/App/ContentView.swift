import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            DeckView()
                .tabItem {
                    Label("Deck", systemImage: "rectangle.stack.fill")
                }

            CameraOCRView()
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.indigo)
    }
}

#Preview {
    ContentView()
        .modelContainer(SharedDataManager.sharedModelContainer)
}
