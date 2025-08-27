import Foundation


struct Zone: Codable, Hashable {
    let id: String
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var audioFile: String? = nil      // optional now (for old single-file mode)
    var colorIndex: Int? = nil
    var stems: [String: Double] = [:] // ⬅️ e.g. ["drums":1.0, "pads":0.6]
}


