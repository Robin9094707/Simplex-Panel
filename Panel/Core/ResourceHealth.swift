import SwiftUI

enum ResourceLoad: String {
    case unknown, low, moderate, high
    static func fraction(value: Double, limit: Double) -> Double? {
        guard value.isFinite, value >= 0, limit.isFinite, limit > 0 else { return nil }
        return value / limit
    }
    static func level(_ fraction: Double?) -> Self {
        guard let fraction, fraction.isFinite, fraction >= 0 else { return .unknown }
        return fraction >= 0.9 ? .high : fraction >= 0.7 ? .moderate : .low
    }
    var color: Color {
        switch self { case .unknown: return .secondary; case .low: return .green; case .moderate: return .yellow; case .high: return .red }
    }
    var title: String {
        switch self { case .unknown: return W("No known limit"); case .low: return W("Low usage"); case .moderate: return W("Elevated usage"); case .high: return W("High usage") }
    }
}
struct ServerHealth {
    let title: String
    let detail: String
    let level: ResourceLoad
    static func assess(state: String, updated: Date?, fractions: [Double?], now: Date = Date()) -> Self {
        guard state == "running" else { return Self(title: state == "offline" ? W("Server offline") : W("Check status"), detail: W("Usage can only be assessed while the server is running."), level: .unknown) }
        guard let updated, now.timeIntervalSince(updated) <= 45 else { return Self(title: W("Metrics are missing or outdated"), detail: W("Refresh to see current usage."), level: .unknown) }
        let known = fractions.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        guard let worst = known.max() else { return Self(title: W("Metrics available"), detail: W("Relative usage cannot be assessed without known limits."), level: .unknown) }
        let level = ResourceLoad.level(worst)
        return Self(title: level == .high ? W("High resource usage") : level == .moderate ? W("Elevated resource usage") : W("Resource usage looks healthy"), detail: W("Assessed \(known.count) of \(fractions.count) resources with known limits. A snapshot, not an availability guarantee."), level: level)
    }
}

