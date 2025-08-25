import SwiftUI
import MapKit
import CoreLocation

// Live location helper (unchanged)
final class LiveLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let last = locs.last { onUpdate?(last) }
    }
}

struct ZoneEditorView: View {
    @EnvironmentObject var manager: SoundWalkManager

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )

    @State private var droppedCoord: CLLocationCoordinate2D?
    @State private var myCoord: CLLocationCoordinate2D?
    @State private var radius: Double = 200
    @State private var title: String = "New Zone"
    @State private var audioFile: String = "deliverance.wav"

    @State private var locator = LiveLocation()

    var body: some View {
        VStack(spacing: 12) {
            MapReader { proxy in
                Map(position: $camera) {
                    // 🔴 Current location as red dot
                    if let me = myCoord {
                        Annotation("Me", coordinate: me) {
                            ZStack {
                                Circle().fill(Color.red.opacity(0.25)).frame(width: 28, height: 28)
                                Circle().fill(Color.red).frame(width: 10, height: 10)
                            }
                        }
                    }

                    // 🟡 Show original Zone A as yellow circle
                    if let zoneA = manager.zones.first(where: { $0.id == "a" }) {
                        let c = CLLocationCoordinate2D(latitude: zoneA.latitude, longitude: zoneA.longitude)
                        MapCircle(center: c, radius: zoneA.radius)
                            .foregroundStyle(Color.yellow.opacity(0.25))
                            .stroke(Color.yellow, lineWidth: 2)
                        Annotation("Zone A", coordinate: c) {
                            Text("A").font(.caption2).padding(4).background(.yellow).clipShape(Circle())
                        }
                    }

                    // 📍 Dropped pin preview
                    if let c = droppedCoord {
                        Annotation("Pin", coordinate: c) {
                            Circle().fill(.blue).frame(width: 10, height: 10)
                        }
                        MapCircle(center: c, radius: radius)
                            .foregroundStyle(.blue.opacity(0.2))
                            .stroke(.blue, lineWidth: 1)
                    }
                }
                // Tap to drop a pin
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        if let coord = proxy.convert(value.location, from: .local) {
                            droppedCoord = coord
                        }
                    }
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            HStack {
                Button("Center on Me") { centerOnUser() }
                Spacer()
                Text("Radius: \(Int(radius)) m")
                Slider(value: $radius, in: 50...300, step: 10).frame(maxWidth: 220)
            }

            HStack {
                TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                TextField("Audio filename (e.g. zone.m4a)", text: $audioFile).textFieldStyle(.roundedBorder)
            }

            Button("Add Zone") {
                guard let c = droppedCoord else { return }
                manager.addZone(Zone(
                    id: UUID().uuidString,
                    title: title.isEmpty ? "Zone" : title,
                    latitude: c.latitude,
                    longitude: c.longitude,
                    radius: radius,
                    audioFile: audioFile
                ))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            locator.onUpdate = { loc in
                myCoord = loc.coordinate
                camera = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
            locator.start()
        }
    }

    private func centerOnUser() {
        if let me = myCoord {
            camera = .region(MKCoordinateRegion(
                center: me,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            locator.start()
        }
    }
}
