import SwiftUI

@main
struct SoundWalkApp: App {
    @StateObject private var manager = SoundWalkManager()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(manager)
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
