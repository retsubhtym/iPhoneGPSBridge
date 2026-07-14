import CoreLocation
import Foundation

struct LocationPacket: Codable {
    let type: String
    let timestamp: String
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let altitudeMeters: Double?
    let verticalAccuracyMeters: Double?
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?

    init(location: CLLocation) {
        type = "location"
        timestamp = ISO8601DateFormatter.gpsBridge.string(from: location.timestamp)
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracyMeters = location.horizontalAccuracy
        altitudeMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
        verticalAccuracyMeters = location.verticalAccuracy >= 0
            ? location.verticalAccuracy
            : nil
        speedMetersPerSecond = location.speed >= 0 ? location.speed : nil
        courseDegrees = location.course >= 0 ? location.course : nil
    }
}

private extension ISO8601DateFormatter {
    static let gpsBridge: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}
