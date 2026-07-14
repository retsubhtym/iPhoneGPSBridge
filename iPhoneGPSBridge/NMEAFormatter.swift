import CoreLocation
import Foundation

enum NMEAFormatter {
    static func sentences(for location: CLLocation) -> String {
        let utc = utcParts(location.timestamp)
        let lat = latitude(location.coordinate.latitude)
        let lon = longitude(location.coordinate.longitude)

        let speedKnots = location.speed >= 0
            ? location.speed * 1.9438444924406
            : 0.0
        let course = location.course >= 0 ? location.course : 0.0

        let valid = location.horizontalAccuracy >= 0 ? "A" : "V"

        let rmcBody = String(
            format: "GPRMC,%@,%@,%@,%@,%@,%@,%.2f,%.2f,%@,,,A",
            utc.time,
            valid,
            lat.value,
            lat.hemisphere,
            lon.value,
            lon.hemisphere,
            speedKnots,
            course,
            utc.date
        )

        let fixQuality = location.horizontalAccuracy >= 0 ? 1 : 0
        let altitude = location.verticalAccuracy >= 0 ? location.altitude : 0.0
        let hdop = max(location.horizontalAccuracy / 5.0, 0.5)

        let ggaBody = String(
            format: "GPGGA,%@,%@,%@,%@,%@,%d,00,%.1f,%.1f,M,0.0,M,,",
            utc.time,
            lat.value,
            lat.hemisphere,
            lon.value,
            lon.hemisphere,
            fixQuality,
            hdop,
            altitude
        )

        return sentence(rmcBody) + sentence(ggaBody)
    }

    private static func sentence(_ body: String) -> String {
        let checksum = body.utf8.reduce(UInt8(0)) { $0 ^ $1 }
        return String(format: "$%@*%02X\r\n", body, checksum)
    }

    private static func latitude(_ degrees: Double) -> (
        value: String,
        hemisphere: String
    ) {
        let absolute = abs(degrees)
        let wholeDegrees = Int(absolute)
        let minutes = (absolute - Double(wholeDegrees)) * 60.0

        return (
            String(format: "%02d%09.6f", wholeDegrees, minutes),
            degrees >= 0 ? "N" : "S"
        )
    }

    private static func longitude(_ degrees: Double) -> (
        value: String,
        hemisphere: String
    ) {
        let absolute = abs(degrees)
        let wholeDegrees = Int(absolute)
        let minutes = (absolute - Double(wholeDegrees)) * 60.0

        return (
            String(format: "%03d%09.6f", wholeDegrees, minutes),
            degrees >= 0 ? "E" : "W"
        )
    }

    private static func utcParts(_ date: Date) -> (
        time: String,
        date: String
    ) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: date
        )

        let time = String(
            format: "%02d%02d%02d.%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            (components.nanosecond ?? 0) / 10_000_000
        )

        let shortYear = (components.year ?? 0) % 100
        let date = String(
            format: "%02d%02d%02d",
            components.day ?? 0,
            components.month ?? 0,
            shortYear
        )

        return (time, date)
    }
}
