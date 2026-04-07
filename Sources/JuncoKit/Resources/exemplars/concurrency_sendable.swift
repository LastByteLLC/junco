// Sendable struct with nonisolated computed property
import Foundation

struct Measurement: Sendable {
    let timestamp: Date
    let sensorID: String
    let value: Double
    let unit: String

    nonisolated var formattedValue: String {
        "\(String(format: "%.2f", value)) \(unit)"
    }

    nonisolated var age: TimeInterval {
        Date.now.timeIntervalSince(timestamp)
    }
}

actor SensorCollector {
    private var readings: [Measurement] = []

    func record(_ measurement: Measurement) {
        readings.append(measurement)
    }

    func latest(for sensorID: String) -> Measurement? {
        readings.last { $0.sensorID == sensorID }
    }

    func averageValue() -> Double {
        guard !readings.isEmpty else { return 0 }
        return readings.reduce(0.0) { $0 + $1.value } / Double(readings.count)
    }
}
