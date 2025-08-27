//
//  StemTransport.swift
//  soundWalk
//
//  Created by Owen on 26/08/2025.
//

import AVFoundation

/// Single transport clock with per-stem players and quantized volume ramps.
final class StemTransport {
    // MARK: Public config
    var bpm: Double = 120          // song tempo
    var beatsPerBar: Int = 4       // time signature top
    var prerollSeconds: Double = 0.15

    // MARK: Internals
    private let engine = AVAudioEngine()
    private let master = AVAudioMixerNode()                  // master mixer
    private var stems: [String: Stem] = [:]                  // id -> stem
    private var transportStartHostTime: UInt64?
    private var sampleRate: Double { engine.mainMixerNode.outputFormat(forBus: 0).sampleRate }

    private struct Stem {
        let id: String
        let file: AVAudioFile
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        var targetGain: Float = 0
    }

    // MARK: Setup
    init() {
        engine.attach(master)
        engine.connect(master, to: engine.mainMixerNode, format: nil)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Resolve a local URL: Documents first, then bundle.
    private func resolveURL(_ filename: String) -> URL? {
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let u = docs.appendingPathComponent(filename)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return Bundle.main.url(forResource: filename, withExtension: nil)
    }

    /// Add a stem before `startAllLooping()`.
    /// filename must be a local file (Documents or bundle).
    func addStem(id: String, filename: String, initialGain: Float = 0) throws {
        guard let url = resolveURL(filename) else { throw NSError(domain: "StemTransport", code: 404, userInfo: [NSLocalizedDescriptionKey: "File \(filename) not found"]) }
        let file = try AVAudioFile(forReading: url)

        let player = AVAudioPlayerNode()
        let mix = AVAudioMixerNode()
        mix.volume = max(0, min(1, initialGain))

        engine.attach(player)
        engine.attach(mix)
        engine.connect(player, to: mix, format: file.processingFormat)
        engine.connect(mix, to: master, format: file.processingFormat)

        stems[id] = Stem(id: id, file: file, player: player, mixer: mix, targetGain: initialGain)
    }

    /// Start all stems in perfect sync and loop them.
    func startAllLooping() throws {
        guard !stems.isEmpty else { return }
        if !engine.isRunning { try engine.start() }

        let nowHT = mach_absolute_time()
        let startHT = hostTime(forSeconds: seconds(forHostTime: nowHT) + prerollSeconds)
        transportStartHostTime = startHT

        for (_, s) in stems {
            scheduleLoop(s, atHostTime: startHT)
            s.player.play(at: AVAudioTime(hostTime: startHT))
        }
    }

    // Loop by rescheduling on completion; keeps file phase consistent.
    private func scheduleLoop(_ s: Stem, atHostTime ht: UInt64?) {
        let file = s.file
        let player = s.player

        // schedule first segment aligned to 'ht'
        player.scheduleFile(file, at: ht != nil ? AVAudioTime(hostTime: ht!) : nil, completionHandler: { [weak self, weak player] in
            guard let self = self, let player = player else { return }
            self.scheduleNextLoop(stemId: s.id)
        })
    }

    private func scheduleNextLoop(stemId: String) {
        guard let s = stems[stemId] else { return }
        s.player.scheduleFile(s.file, at: nil, completionHandler: { [weak self] in
            self?.scheduleNextLoop(stemId: stemId)
        })
    }

    // MARK: Quantized gain control
    /// Set a stem's gain with a ramp, quantized to the next bar (or n bars).
    func setStem(_ id: String, gain: Float, fadeSeconds: Double = 1.2, quantizeBars: Int = 1) {
        guard let s = stems[id], let startHT = transportStartHostTime else { return }
        let clamped = max(0, min(1, gain))
        stems[id]?.targetGain = clamped

        let targetHT = nextQuantizedHostTime(from: mach_absolute_time(), transportStartHT: startHT, bars: quantizeBars)
        rampVolume(node: s.mixer, to: clamped, duration: fadeSeconds, startHostTime: targetHT)
    }

    // MARK: Helpers
    private func secondsPerBar() -> Double { (60.0 / bpm) * Double(beatsPerBar) }

    private func nextQuantizedHostTime(from nowHT: UInt64, transportStartHT: UInt64, bars: Int) -> UInt64 {
        let now = seconds(forHostTime: nowHT)
        let t0  = seconds(forHostTime: transportStartHT)
        let quantum = secondsPerBar() * Double(max(1, bars))
        let rel = max(0, now - t0)
        let n = ceil(rel / quantum)
        let tNext = t0 + n * quantum
        return hostTime(forSeconds: tNext)
    }

    private func seconds(forHostTime ht: UInt64) -> Double { AVAudioTime.seconds(forHostTime: ht) }
    private func hostTime(forSeconds s: Double) -> UInt64 { AVAudioTime.hostTime(forSeconds: s) }

    // Smooth ramp using Dispatch timers (20 steps).
    private func rampVolume(node: AVAudioMixing, to target: Float, duration: Double, startHostTime: UInt64) {
        let startSecs = seconds(forHostTime: startHostTime)
        let delay = max(0, startSecs - CACurrentMediaTime())
        let steps = 20
        let stepDur = duration / Double(steps)
        let startVol = node.volume

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            for i in 1...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDur * Double(i)) {
                    let t = Float(i) / Float(steps)
                    node.volume = startVol + (target - startVol) * t
                }
            }
        }
    }
}

