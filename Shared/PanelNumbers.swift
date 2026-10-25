import Foundation

enum PanelNumbers {
    static func number(_ value: JSON) -> Double? {
        guard value != .null, let number = Double(value.string.replacingOccurrences(of: ",", with: ".")), number.isFinite, number >= 0 else { return nil }
        return number
    }
}
enum PanelProvider: String, Codable { case pterodactyl
    var title: String { "Pterodactyl" }
}
