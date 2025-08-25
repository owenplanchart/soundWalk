import SwiftUI
import MapKit

struct ZoneEditorView: View {
    @EnvironmentObject var manager: SoundWalkManager

    // Map camera (iOS 17 style)
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )

    @State private var droppedCoord: CLLocationCoordinate2D?
    @State private var radius: Double = 200
    @State private var title: String = "New Zone"
    @State private var audioFile: String = "ClockTick.wav"

    var body: some View {
        VStack(spacing: 12) {
            MapReader { proxy in
                Map(position: $camera) {
                    if let c = droppedCoord {
                        Annotation("Pin", coordinate: c) {
                            Circle().fill(.blue).frame(width: 10, height: 10)
                        }
                        MapCircle(center: c, radius: radius)
                            .foregroundStyle(.blue.opacity(0.2))
                            .stroke(.blue, lineWidth: 1)
                    }
                }
                // Long-press to drop a pin at touch location
                .gesture(
                    SpatialTapGesture(count: 1).onEnded { value in
                        if let coord = proxy.convert(value.location, from: .local) {
                            droppedCoord = coord
                        }
                    }
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            HStack {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Audio filename (e.g. zone.m4a)", text: $audioFile)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Radius: \(Int(radius)) m")
                Slider(value: $radius, in: 50...300, step: 10)
            }

            Button("Add Zone") {
                guard let c = droppedCoord else { return }
                let z = Zone(
                    id: UUID().uuidString,
                    title: title.isEmpty ? "Zone" : title,
                    latitude: c.latitude,
                    longitude: c.longitude,
                    radius: radius,
                    audioFile: audioFile
                )
                manager.addZone(z)       // updates geofences
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
