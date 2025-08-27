import SwiftUI
import AVFoundation

final class SoundWalkManager: NSObject, ObservableObject {
    // UI
    @Published var insideIds: Set<String> = []
    @Published var zones: [Zone] = []

    // Location + audio
    private let loc = LocationService()
    private let transport = StemTransport()

    // Active zones for overlap-safe mixing
    private var activeZoneIds = Set<String>()

    // Persist (Documents/zones.json)
    private let zonesURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("zones.json")
    }()

    // Helpers
    private func stemId(forFilename name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    // MARK: - Init
    override init() {
        super.init()

        // Register all available audio as stems (Bundle + Documents)
        let files = audioLibraryFiles()
        for f in files { try? transport.addStem(id: stemId(forFilename: f), filename: f, initialGain: 0) }
        transport.bpm = 98; transport.beatsPerBar = 4
        try? transport.startAllLooping()
        print("Registered stems:", files.map { stemId(forFilename: $0) })

        // Geofence hooks
        loc.onEnter = { [weak self] z in self?.zoneDidEnter(z) }
        loc.onExit  = { [weak self] z in self?.zoneDidExit(z) }

        loadZonesIfNeeded()
    }

    func start() { loc.start(for: zones) }

    // MARK: - Overlap-safe mixing
    private func refreshMix() {
        // Compute target gain per stem as MAX across all active zones
        var target: [String: Double] = [:]

        for z in zones where activeZoneIds.contains(z.id) {
            // Stems map
            for (sid, g) in z.stems { target[sid] = max(target[sid] ?? 0, g) }
            // Fallback: single-file zones act as stem with gain 1.0
            if let f = z.audioFile {
                let sid = stemId(forFilename: f)
                target[sid] = max(target[sid] ?? 0, 1.0)
            }
        }

        // Apply gains
        for (sid, g) in target {
            transport.setStem(sid, gain: Float(g), fadeSeconds: 1.2, quantizeBars: 1)
        }
        // Mute any stems not requested by any active zone (optional, only for known stems)
        // If you want strict muting, list known stems and set to 0 when absent.
    }

    private func zoneDidEnter(_ z: Zone) {
        insideIds.insert(z.id)
        activeZoneIds.insert(z.id)
        refreshMix()
        print("ENTER \(z.title)")
    }

    private func zoneDidExit(_ z: Zone) {
        insideIds.remove(z.id)
        activeZoneIds.remove(z.id)
        refreshMix()
        print("EXIT  \(z.title)")
    }

    // MARK: - Zone management
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
        // Remove vanished zones from active set
        let oldIds = Set(zones.map(\.id))
        let newIds = Set(newZones.map(\.id))
        let removed = oldIds.subtracting(newIds)
        activeZoneIds.subtract(removed)

        zones = newZones
        saveZones()
        loc.start(for: zones)  // re-arm geofences
        refreshMix()
    }

    // MARK: - Persistence
    private func loadZonesIfNeeded() {
        if FileManager.default.fileExists(atPath: zonesURL.path) {
            do { zones = try JSONDecoder().decode([Zone].self, from: Data(contentsOf: zonesURL)) }
            catch {
                print("loadZones error:", error)
                zones = defaultSeedZones(); saveZones()
            }
        } else {
            zones = defaultSeedZones(); saveZones()
        }
    }

    private func saveZones() {
        do { try JSONEncoder().encode(zones).write(to: zonesURL, options: .atomic) }
        catch { print("saveZones error:", error) }
    }

    private func defaultSeedZones() -> [Zone] {
        [
            .init(id:"a", title:"Zone A", latitude:51.474753, longitude:-0.057528,
                  radius:200, audioFile:nil, colorIndex:0, stems:["drums":1.0, "pads":0.6]),
            .init(id:"b", title:"Zone B", latitude:51.500, longitude:-0.120000,
                  radius:150, audioFile:nil, colorIndex:1, stems:["bass":1.0, "vox":0.8]),
        ]
    }

    // MARK: - Audio library helpers
    func bundleAudioFiles() -> [String] {
        let exts = ["m4a","wav","mp3","caf"]
        var names = Set<String>()
        for ext in exts {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                urls.forEach { names.insert($0.lastPathComponent) }
            }
        }
        return names.sorted()
    }

    func audioLibraryFiles() -> [String] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?
            .filter { ["m4a","wav","mp3","caf"].contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent } ?? []
        return Array(Set(docFiles + bundleAudioFiles())).sorted()
    }

    func resolveAudioURL(filename: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docURL = docs.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: docURL.path) { return docURL }
        return Bundle.main.url(forResource: filename, withExtension: nil)
    }
}

