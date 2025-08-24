import SwiftUI
import CoreLocation
import AVFoundation

// === Configure your spot & audio ===
let spot = (lat: 51.474753, lon: -0.057528, radiusM: 80.0)
let audioFilename = "familyUnits.wav" // add to target
//let audioFilename = "ClockTick.wav" // add to target
//let audioFilename = "Ron1.m4a" // add to target

@main
struct SoundWalkApp: App {
    @StateObject private var vm = SoundWalkVM()
    var body: some Scene { WindowGroup { ContentView().environmentObject(vm) } }
}

final class SoundWalkVM: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var inside = false
    private let lm = CLLocationManager()
    private var player: AVAudioPlayer?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        // 1) Ask When-In-Use first; we'll upgrade to Always after grant.
        lm.requestWhenInUseAuthorization()

        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func start() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let center = CLLocationCoordinate2D(latitude: spot.lat, longitude: spot.lon)
        let region  = CLCircularRegion(center: center,
                                       radius: max(50, spot.radiusM),
                                       identifier: "spot")
        region.notifyOnEntry = true
        region.notifyOnExit  = true
        lm.startUpdatingLocation()
        lm.startMonitoring(for: region)
        if let loc = lm.location, region.contains(loc.coordinate) { enterRegion() }
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse:
            // 2) Upgrade to Always (this triggers the second system prompt)
            m.requestAlwaysAuthorization()
        case .authorizedAlways:
            start()
        default: break
        }
    }
    func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) { enterRegion() }
    func locationManager(_ m: CLLocationManager, didExitRegion  region: CLRegion) { exitRegion() }

    // MARK: - Audio
    private func enterRegion() {
        inside = true
        guard player == nil else { fade(to: 1.0); return }
        guard let url = Bundle.main.url(forResource: audioFilename, withExtension: nil) else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.0
            p.prepareToPlay()
            p.play()
            player = p
            fade(to: 1.0)
        } catch { print("Audio error:", error) }
    }
    private func exitRegion() {
        inside = false
        fade(to: 0.0) { [weak self] in self?.player?.stop(); self?.player = nil }
    }
    private func fade(to target: Float, seconds: TimeInterval = 2.0, completion: (() -> Void)? = nil) {
        guard let p = player else { completion?(); return }
        let steps = 20, start = p.volume
        (1...steps).forEach { i in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds * Double(i)/Double(steps)) {
                p.volume = start + (target - start) * Float(i)/Float(steps)
                if i == steps { completion?() }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var vm: SoundWalkVM
    var body: some View {
        VStack(spacing: 16) {
            Text(vm.inside ? "🎧 Inside zone — playing" : "🧭 Outside zone — silent").font(.title3)
            Button("Start Monitoring") { vm.start() }.buttonStyle(.borderedProminent)
            Text("Lat \(spot.lat), Lon \(spot.lon), R \(Int(spot.radiusM))m")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
    }
}
