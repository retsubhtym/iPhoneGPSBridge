import CoreLocation
import Foundation
import Network
internal import Combine

@MainActor
final class GPSBridge: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var serverStatus = "Stopped"
    @Published private(set) var clientCount = 0
    @Published private(set) var authorizationText = "Unknown"

    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published private(set) var horizontalAccuracy: Double?
    @Published private(set) var altitude: Double?
    @Published private(set) var speed: Double?
    @Published private(set) var lastError: String?

    let port: UInt16 = 10110

    private let locationManager = CLLocationManager()
    private let server = TCPLocationServer()
    private let encoder = JSONEncoder()
    private var latestLocation: CLLocation?
    private var broadcastTask: Task<Void, Never>?

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        encoder.outputFormatting = [.sortedKeys]

        server.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.serverStatus = state
            }
        }

        server.onClientCountChange = { [weak self] count in
            guard let self else { return }
            Task { @MainActor in
                self.clientCount = count
            }
        }

        updateAuthorizationText()
    }

    func start() {
        guard !isRunning else { return }

        lastError = nil
        requestWhenInUseIfNeeded()

        do {
            try server.start(port: port)
            locationManager.startUpdatingLocation()
            isRunning = true
            startBroadcastLoop()
        } catch {
            lastError = error.localizedDescription
            serverStatus = "Failed"
            server.stop()
        }
    }

    func stop() {
        broadcastTask?.cancel()
        broadcastTask = nil
        locationManager.stopUpdatingLocation()
        server.stop()
        isRunning = false
        serverStatus = "Stopped"
        clientCount = 0
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    private func requestWhenInUseIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            lastError = "Location permission is denied. Enable it in Settings."
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }
    }

    private func updateAuthorizationText() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            authorizationText = "Not requested"
        case .restricted:
            authorizationText = "Restricted"
        case .denied:
            authorizationText = "Denied"
        case .authorizedAlways:
            authorizationText = "Always"
        case .authorizedWhenInUse:
            authorizationText = "While using"
        @unknown default:
            authorizationText = "Unknown"
        }
    }

    private func publish(_ location: CLLocation) {
        latestLocation = location
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        speed = location.speed >= 0 ? location.speed : nil
    }

    private func startBroadcastLoop() {
        broadcastTask?.cancel()
        broadcastTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.broadcastLatestLocation()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func broadcastLatestLocation() {
        guard let location = latestLocation else { return }

        let packet = LocationPacket(location: location)

        do {
            let json = try encoder.encode(packet)
            server.broadcast(json + Data([0x0A]))

            let nmea = NMEAFormatter.sentences(for: location)
            server.broadcast(Data(nmea.utf8))
        } catch {
            lastError = "Encoding failed: \(error.localizedDescription)"
        }
    }
}

extension GPSBridge: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.updateAuthorizationText()

            guard let self, self.isRunning else { return }
            if manager.authorizationStatus == .authorizedAlways ||
               manager.authorizationStatus == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        Task { @MainActor [weak self] in
            self?.publish(location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.lastError = error.localizedDescription
        }
    }
}
