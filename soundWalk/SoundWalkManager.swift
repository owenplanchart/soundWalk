import SwiftUI
import AVFoundation

final class SoundWalkManager: NSObject, ObservableObject {
    @Published var insideIds: Set<String> = []
    @Published var zones: [Zone] = [ // ← mutable
        .init(id:"a", title:"Zone A", latitude:51.474753, longitude:-0.057528, radius:200, audioFile:"familyUnits.wav"),
        .init(id:"b", title:"Zone B", latitude:51.500,    longitude:-0.120000, radius:150, audioFile:"b.m4a"),
    ]

    private let loc = LocationService()
    private var players: [String: AVAudioPlayer] = [:]

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        loc.onEnter = { [weak self] z in self?.play(z) }
        loc.onExit  = { [weak self] z in self?.stop(z) }
    }

    func start() { loc.start(for: zones) }

    // Add/refresh zones at runtime
    func addZone(_ z: Zone) {
        zones.append(z)
        loc.start(for: zones) // refresh geofences
    }

    private func play(_ zone: Zone) {
        insideIds.insert(zone.id)
        if players[zone.id] == nil,
           let url = Bundle.main.url(forResource: zone.audioFile, withExtension: nil),
           let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = -1
            p.volume = 0
            p.play()
            players[zone.id] = p
            fade(p, to: 1)
        } else if let p = players[zone.id] {
            fade(p, to: 1)
        }
    }

    private func stop(_ zone: Zone) {
        insideIds.remove(zone.id)
        if let p = players[zone.id] {
            fade(p, to: 0) { p.stop(); self.players.removeValue(forKey: zone.id) }
        }
    }

    private func fade(_ p: AVAudioPlayer, to target: Float, seconds: TimeInterval = 1.5, completion: (() -> Void)? = nil) {
        let steps = 20, start = p.volume
        (1...steps).forEach { i in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds * Double(i)/Double(steps)) {
                p.volume = start + (target - start) * Float(i)/Float(steps)
                if i == steps { completion?() }
            }
        }
    }
}
