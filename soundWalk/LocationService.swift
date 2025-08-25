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
        print("Me:", loc.coordinate.latitude, loc.coordinate.longitude)
        debugDistances(allZones, current: loc)
    }
    
    private func activateRegions(near location: CLLocation, zones: [Zone]) {
        // Pick nearest ≤20
        let active = zones.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) <
            CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: location)
        }.prefix(20)

        // 1) For any old region we’re dropping, synthesize EXIT if we were inside it
        let newIds = Set(active.map { $0.id })
        for (oldId, oldZone) in zoneByRegionId where !newIds.contains(oldId) {
            let c = CLLocationCoordinate2D(latitude: oldZone.latitude, longitude: oldZone.longitude)
            let oldRegion = CLCircularRegion(center: c, radius: max(50, oldZone.radius), identifier: oldZone.id)
            if oldRegion.contains(location.coordinate) { onExit(oldZone) }
        }

        // 2) Clear and install new regions
        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        zoneByRegionId.removeAll()

        for zone in active {
            let c = CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)
            let r = CLCircularRegion(center: c, radius: max(50, zone.radius), identifier: zone.id)
            r.notifyOnEntry = true
            r.notifyOnExit  = true
            zoneByRegionId[zone.id] = zone
            manager.startMonitoring(for: r)

            // If already inside -> ENTER now; otherwise force an EXIT (idempotent if nothing playing)
            if r.contains(location.coordinate) { onEnter(zone) }
            else { onExit(zone) }
        }

        print("Monitored regions:", manager.monitoredRegions.count)
    }


    func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        if let zone = zoneByRegionId[region.identifier] { onEnter(zone) }
    }
    func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        if let zone = zoneByRegionId[region.identifier] { onExit(zone) }
    }
}
