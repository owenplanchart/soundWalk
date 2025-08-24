import Foundation

struct Zone: Decodable, Hashable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let audioFile: String
}

