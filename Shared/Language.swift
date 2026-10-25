import Foundation

struct WingText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var key: String
    var values: [String] = []
    init(stringLiteral value: String) { key = value }
    init(stringInterpolation value: StringInterpolation) { key = value.key; values = value.values }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var values: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); values.reserveCapacity(interpolationCount) }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) { key += "{{\(values.count)}}"; values.append(String(describing: value)) }
    }
}
enum WingLanguage {
    static var code: String {
        if let saved = UserDefaults.standard.string(forKey: "wing.language") { return saved }
        if let group = SigningGroups.availableGroup, let saved = UserDefaults(suiteName: group)?.string(forKey: "wing.language") { return saved }
        return Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    }
    static let german: [String: String] = {
        guard let url = Bundle.main.url(forResource: "German", withExtension: "json"), let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return result
    }()
    static func render(_ text: WingText, code: String? = nil) -> String {
        var result = (code ?? self.code) == "de" ? german[text.key] ?? text.key : text.key
        // Replace once, so user content containing a placeholder is never interpreted again.
        let parts = result.components(separatedBy: "{{")
        guard parts.count > 1 else { return result }
        result = parts[0]
        for part in parts.dropFirst() {
            if let end = part.range(of: "}}"), let index = Int(part[..<end.lowerBound]), text.values.indices.contains(index) { result += text.values[index] + part[end.upperBound...] }
            else { result += "{{" + part }
        }
        return result
    }
}
func W(_ text: WingText) -> String { WingLanguage.render(text) }
