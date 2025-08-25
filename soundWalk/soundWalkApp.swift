import SwiftUI

@main
struct soundWalkApp: App {
    @StateObject private var manager = SoundWalkManager()
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView().environmentObject(manager)
                    .tabItem { Label("Run", systemImage: "play.circle") }
                ZoneEditorView().environmentObject(manager)
                    .tabItem { Label("Zones", systemImage: "mappin.and.ellipse") }
            }
        }
    }
    
    struct ContentView: View {
        @EnvironmentObject var manager: SoundWalkManager
        var body: some View {
            VStack(spacing: 16) {
                if manager.insideIds.isEmpty {
                    Text("🧭 Outside all zones")
                } else {
                    Text("🎧 Inside: \(manager.insideIds.joined(separator: ", "))")
                }
                Button("Start Monitoring") { manager.start() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
