import Foundation

struct Zone: Codable, Hashable {
    let id: String
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var audioFile: String
    var colorIndex: Int? = nil
}

