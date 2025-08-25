import SwiftUI
import MapKit
import CoreLocation

// Live location helper (continuous)
final class LiveLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: ((CLLocation) -> Void)?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
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

// Stable palette (use z.colorIndex if you persisted it)
private let zoneColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .brown, .cyan]

struct ZoneEditorView: View {
    @EnvironmentObject var manager: SoundWalkManager

    // Map
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 51.5074, longitude: -0.1278),
                           span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02))
    )
    @State private var myCoord: CLLocationCoordinate2D?

    // Editing model
    @State private var selectedId: String? = nil     // nil = creating new
    @State private var title: String = ""
    @State private var radius: Double = 200
    @State private var audioFile: String = ""
    @State private var centerCoord: CLLocationCoordinate2D? = nil

    // Dropdown data
    @State private var audioOptions: [String] = []

    @State private var locator = LiveLocation()

    var body: some View {
        VStack(spacing: 10) {
            // --- Top controls: pick zone & audio ---
            HStack(spacing: 10) {
                // Zone dropdown
                Picker("Zone", selection: Binding(
                    get: { selectedId ?? "NEW" },
                    set: { newVal in
                        if newVal == "NEW" { clearEditor() }
                        else if let z = manager.zones.first(where: { $0.id == newVal }) { loadForEdit(z) }
                    }
                )) {
                    Text("➕ New Zone").tag("NEW")
                    ForEach(manager.zones, id: \.id) { z in
                        Text(z.title.isEmpty ? z.id : z.title).tag(z.id)
                    }
                }
                .pickerStyle(.menu)

                // Audio dropdown
                Picker("Audio", selection: $audioFile) {
                    if audioOptions.isEmpty { Text("No audio in bundle").tag("") }
                    ForEach(audioOptions, id: \.self) { name in Text(name).tag(name) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            // --- Map with all zones + editing preview + my red dot ---
            MapReader { proxy in
                Map(position: $camera) {
                    // me (red dot)
                    if let me = myCoord {
                        Annotation("Me", coordinate: me) {
                            ZStack {
                                Circle().fill(Color.red.opacity(0.25)).frame(width: 28, height: 28)
                                Circle().fill(Color.red).frame(width: 10, height: 10)
                            }
                        }
                    }

                    // all zones
                    ForEach(Array(manager.zones.enumerated()), id: \.1.id) { idx, z in
                        let c = CLLocationCoordinate2D(latitude: z.latitude, longitude: z.longitude)
                        let col: Color = {
                            if let ci = z.colorIndex { return zoneColors[ci % zoneColors.count] }
                            return zoneColors[idx % zoneColors.count]
                        }()
                        MapCircle(center: c, radius: z.radius)
                            .foregroundStyle(col.opacity(0.18))
                            .stroke(col, lineWidth: (z.id == selectedId ? 3 : 1.5))
                        Annotation(z.title.isEmpty ? "Zone" : z.title, coordinate: c) {
                            Text(z.title.isEmpty ? "Zone" : z.title)
                                .font(.caption2).padding(4)
                                .background(col.opacity(0.85)).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // editing preview
                    if let c = centerCoord {
                        MapCircle(center: c, radius: radius)
                            .foregroundStyle(Color.gray.opacity(0.12))
                            .stroke(Color.gray, lineWidth: 1)
                        Annotation("Editing", coordinate: c) {
                            Circle().fill(Color.gray).frame(width: 10, height: 10)
                        }
                    }
                }
                // tap to set/move center
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        if let coord = proxy.convert(value.location, from: .local) {
                            centerCoord = coord
                            if selectedId == nil && title.isEmpty {
                                title = "Zone \(manager.zones.count + 1)"
                            }
                        }
                    }
                )
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // --- Radius + actions ---
            HStack {
                Button("Center on Me") { centerOnUser() }
                Spacer()
                Text("Radius: \(Int(radius)) m")
                Slider(value: $radius, in: 50...500, step: 10).frame(maxWidth: 240)
            }

            HStack {
                TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(selectedId == nil ? "Add Zone" : "Update Zone") { addOrUpdate() }
                    .buttonStyle(.borderedProminent)
                if selectedId != nil {
                    Button("Delete") { deleteSelected() }
                        .buttonStyle(.bordered).tint(.red)
                }
                Spacer()
            }
        }
        .padding()
        .onAppear {
            // live location
            locator.onUpdate = { loc in
                myCoord = loc.coordinate
                camera = .region(MKCoordinateRegion(center: loc.coordinate,
                                                    span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            }
            locator.start()
            // audio options from bundle
            audioOptions = manager.bundleAudioFiles()
            // optional: preselect first zone for editing
            if let first = manager.zones.first { loadForEdit(first) }
            else { clearEditor() }
        }
    }

    // MARK: - Actions
    private func addOrUpdate() {
        guard let c = centerCoord, !audioFile.isEmpty else { return }
        let id = selectedId ?? UUID().uuidString
        // keep colorIndex if editing
        let existingColorIndex = manager.zones.first(where: { $0.id == id })?.colorIndex
        let z = Zone(id: id, title: title.isEmpty ? "Zone" : title,
                     latitude: c.latitude, longitude: c.longitude,
                     radius: radius, audioFile: audioFile,
                     colorIndex: existingColorIndex)
        manager.addOrReplaceZone(z)
        selectedId = id
    }

    private func deleteSelected() {
        guard let id = selectedId else { return }
        let next = manager.zones.filter { $0.id != id }
        manager.refreshZones(next)
        clearEditor()
    }

    private func loadForEdit(_ z: Zone) {
        selectedId = z.id
        title = z.title
        radius = z.radius
        audioFile = z.audioFile
        centerCoord = CLLocationCoordinate2D(latitude: z.latitude, longitude: z.longitude)
        camera = .region(MKCoordinateRegion(center: centerCoord!,
                                            span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }

    private func clearEditor() {
        selectedId = nil
        title = ""
        radius = 200
        audioFile = audioOptions.first ?? ""
        centerCoord = myCoord // default draft at my location if available
    }

    private func centerOnUser() {
        if let me = myCoord {
            camera = .region(MKCoordinateRegion(center: me,
                                                span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        }
    }
}

