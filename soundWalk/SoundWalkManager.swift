import SwiftUI
import AVFoundation

final class SoundWalkManager: NSObject, ObservableObject {
    @Published var insideIds: Set<String> = []
    @Published var zones: [Zone] = []           // loaded from disk

    private let loc = LocationService()
    private var players: [String: AVAudioPlayer] = [:]

    // Persist to Documents/zones.json
    private let zonesURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("zones.json")
    }()

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        loc.onEnter = { [weak self] z in self?.play(z) }
        loc.onExit  = { [weak self] z in self?.stop(z) }

        loadZonesIfNeeded()   // seed or load
    }
    

    func start() { loc.start(for: zones) }

    // MARK: - Zone management (add / replace / persist)
    func addOrReplaceZone(_ z: Zone) {
        var next = zones
        if let i = next.firstIndex(where: { $0.id == z.id || $0.title == z.title }) {
            next[i] = z
        } else {
            var z2 = z
            if z2.colorIndex == nil {
                z2.colorIndex = ((zones.compactMap { $0.colorIndex }.max() ?? -1) + 1)
            }
            next.append(z2)
        }
        refreshZones(next)
    }

    func refreshZones(_ newZones: [Zone]) {
        // stop players for removed zones
        let oldIds = Set(zones.map { $0.id })
        let newIds = Set(newZones.map { $0.id })
        for removedId in oldIds.subtracting(newIds) {
            if let z = zones.first(where: { $0.id == removedId }) { stop(z) }
        }
        zones = newZones
        saveZones()
        loc.start(for: zones)
    }

    // MARK: - Persistence
    private func loadZonesIfNeeded() {
        if FileManager.default.fileExists(atPath: zonesURL.path) {
            do {
                zones = try JSONDecoder().decode([Zone].self, from: Data(contentsOf: zonesURL))
            } catch {
                print("loadZones error:", error)
                zones = defaultSeedZones()
                saveZones()
            }
        } else {
            zones = defaultSeedZones()
            saveZones()
        }
    }

    private func saveZones() {
        do {
            let data = try JSONEncoder().encode(zones)
            try data.write(to: zonesURL, options: .atomic)
        } catch {
            print("saveZones error:", error)
        }
    }

    private func defaultSeedZones() -> [Zone] {
        [
            .init(id:"a", title:"Zone A", latitude:51.474753, longitude:-0.057528,
                  radius:200, audioFile:"cello.wav",       colorIndex: 0),
            .init(id:"b", title:"Zone B", latitude:51.500,    longitude:-0.120000,
                  radius:150, audioFile:"deliverance.wav",   colorIndex: 1)
        ]
    }

    // MARK: - Audio
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
    // Discover bundled audio filenames (.m4a, .wav, .mp3, .caf)
    func bundleAudioFiles() -> [String] {
        let exts = ["m4a","wav","mp3","caf"]
        var names: Set<String> = []
        for ext in exts {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for u in urls { names.insert(u.lastPathComponent) }
            }
        }
        // Stable order, show .m4a first (smaller files)
        return names.sorted { (a, b) in
            let pa = (a as NSString).pathExtension.lowercased()
            let pb = (b as NSString).pathExtension.lowercased()
            if pa == pb { return a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
            // m4a first, then wav, mp3, caf
            let rank: [String:Int] = ["m4a":0,"wav":1,"mp3":2,"caf":3]
            return (rank[pa] ?? 9) < (rank[pb] ?? 9)
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

