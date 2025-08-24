import CoreLocation

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onEnter: (Zone) -> Void = { _ in }
    var onExit: (Zone) -> Void = { _ in }
    private var zoneByRegionId: [String: Zone] = [:]
    private var allZones: [Zone] = []

    func start(for zones: [Zone]) {
        allZones = zones
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            manager.startUpdatingLocation()
        case .authorizedAlways:
            manager.startUpdatingLocation()
            // If we already have a location, set up regions immediately
            if let loc = manager.location { activateRegions(near: loc, zones: allZones) }
        default:
            break
        }
    }

    func debugDistances(_ zones: [Zone], current: CLLocation) {
        for z in zones {
            let d = current.distance(from: CLLocation(latitude: z.latitude, longitude: z.longitude))
            print("Zone \(z.id): \(Int(d)) m away (R=\(Int(z.radius)))")
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse {
            m.requestAlwaysAuthorization()
        }
        if m.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        if manager.monitoredRegions.isEmpty {
            activateRegions(near: loc, zones: allZones)
        }
        // Debug: print distances to each zone
        debugDistances(allZones, current: loc)
    }

    private func activateRegions(near location: CLLocation, zones: [Zone]) {
        let active = zones.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) <
            CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: location)
        }.prefix(20)

        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        zoneByRegionId.removeAll()

        active.forEach { zone in
            let c = CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)
            let r = CLCircularRegion(center: c, radius: max(50, zone.radius), identifier: zone.id)
            r.notifyOnEntry = true
            r.notifyOnExit  = true
            zoneByRegionId[zone.id] = zone
            manager.startMonitoring(for: r)

            // ⬇️ trigger immediately if we’re already inside
            if let cur = manager.location, r.contains(cur.coordinate) {
                onEnter(zone)
               
            }
        }
    }

    func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        if let zone = zoneByRegionId[region.identifier] { onEnter(zone) }
    }
    func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        if let zone = zoneByRegionId[region.identifier] { onExit(zone) }
    }
}
