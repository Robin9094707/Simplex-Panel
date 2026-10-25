import Foundation
import zlib
import CryptoKit

struct PluginDescriptor: Equatable, Sendable {
    let name: String
    let version: String
    let main: String
    let apiVersion: String
    var summary = ""
    var author = ""
    var website = ""
    var descriptorFile = "plugin.yml"
    var rawYAML = ""
    var versionedFilename: String {
        func safe(_ value: String, fallback: String) -> String {
            let clean = value.replacingOccurrences(of: "[^A-Za-z0-9._+-]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            return clean.isEmpty ? fallback : String(clean.prefix(80))
        }
        return safe(name, fallback: "Plugin") + "-" + safe(version, fallback: "version") + ".jar"
    }
    static func parse(_ text: String) throws -> PluginDescriptor {
        var fields: [String: String] = [:]
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]); guard ["name", "version", "main", "api-version", "description", "author", "authors", "website"].contains(key) else { continue }
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = ConfigurationField.decodeYAML(value)?.value ?? value.components(separatedBy: " #")[0].trimmingCharacters(in: .whitespaces)
            if (key == "authors" && value.isEmpty) || (key == "description" && ["|", ">", "|-", ">-"].contains(value)) {
                let body = lines.dropFirst(index + 1).prefix { $0.hasPrefix(" ") || $0.hasPrefix("\t") || $0.isEmpty }
                if key == "authors" { fields[key] = body.compactMap { item -> String? in
                    let row = item.trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("- ") else { return nil }
                    let raw = String(row.dropFirst(2))
                    return ConfigurationField.decodeYAML(raw)?.value ?? raw
                }.joined(separator: ", ") }
                else { fields[key] = body.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: value.hasPrefix(">") ? " " : "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        guard let name = fields["name"], !name.isEmpty, let version = fields["version"], !version.isEmpty, let main = fields["main"], !main.isEmpty else { throw PanelError(message: W("Missing plugin metadata: plugin.yml or paper-plugin.yml must contain name, version and main.")) }
        guard name.utf8.count <= 256, version.utf8.count <= 256, main.utf8.count <= 1024 else { throw PanelError(message: W("Plugin metadata contains unusually long identity fields.")) }
        return PluginDescriptor(name: name, version: version, main: main, apiVersion: fields["api-version"] ?? W("Not specified"), summary: String((fields["description"] ?? "").prefix(4000)), author: String((fields["author"] ?? fields["authors"] ?? "").prefix(2000)), website: String((fields["website"] ?? "").prefix(2000)), rawYAML: text)
    }
    func validateUpdate(_ next: PluginDescriptor) throws -> String {
        guard name == next.name, main == next.main else { throw PanelError(message: W("Wrong plugin. Expected: \(name) (\(main)); selected: \(next.name) (\(next.main)).")) }
        guard version != next.version else { throw PanelError(message: W("Version \(version) is already installed.")) }
        let numeric = #"^\d+(\.\d+){0,4}$"#
        if version.range(of: numeric, options: .regularExpression) != nil && next.version.range(of: numeric, options: .regularExpression) != nil {
            guard next.version.compare(version, options: .numeric) == .orderedDescending else { throw PanelError(message: W("Selected version \(next.version) is not newer than \(version).")) }
            return W("Plugin name, main class and higher version number verified.")
        }
        return W("Plugin name and main class match. These version labels cannot be ordered reliably.")
    }
}
enum PluginArchive {
    static func descriptor(_ data: Data) throws -> PluginDescriptor {
        let descriptors = try metadata(data, names: ["plugin.yml", "paper-plugin.yml"])
        guard let yaml = descriptors["paper-plugin.yml"] ?? descriptors["plugin.yml"] else { throw PanelError(message: W("The JAR contains neither plugin.yml nor paper-plugin.yml. This is not a Paper/Bukkit plugin.")) }
        var descriptor = try PluginDescriptor.parse(yaml)
        descriptor.descriptorFile = descriptors["paper-plugin.yml"] != nil ? "paper-plugin.yml" : "plugin.yml"
        return descriptor
    }
    static func metadata(_ data: Data, names: Set<String>) throws -> [String: String] {
        guard data.count >= 22 && data.count <= 128 * 1024 * 1024 else { throw PanelError(message: W("Invalid plugin JAR or larger than 128 MiB.")) }
        func n(_ offset: Int, _ count: Int) throws -> Int { guard offset >= 0 && offset + count <= data.count else { throw PanelError(message: W("Corrupted ZIP directory.")) }; return Int(data.uintLE(offset, count)) }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) { if try n(i, 4) == 0x06054b50 && i + 22 + n(i + 20, 2) == data.count { end = i; break } }
        guard let end, try n(end + 4, 2) == 0, try n(end + 6, 2) == 0 else { throw PanelError(message: W("Unsupported JAR/ZIP file.")) }
        let count = try n(end + 10, 2); var cursor = try n(end + 16, 4)
        guard count < 65535 else { throw PanelError(message: W("ZIP64 is not supported for plugin metadata.")) }
        var descriptors: [String: String] = [:]
        for _ in 0..<count {
            guard try n(cursor, 4) == 0x02014b50 else { throw PanelError(message: W("Invalid ZIP entry.")) }
            let nameCount = try n(cursor + 28, 2), extra = try n(cursor + 30, 2), comment = try n(cursor + 32, 2)
            guard cursor + 46 + nameCount + extra + comment <= data.count else { throw PanelError(message: W("Truncated ZIP entry.")) }
            let name = String(decoding: data[cursor + 46..<cursor + 46 + nameCount], as: UTF8.self)
            if names.contains(name) {
                guard descriptors[name] == nil, try n(cursor + 8, 2) & 1 == 0 else { throw PanelError(message: W("Ambiguous or encrypted plugin metadata.")) }
                let packed = try n(cursor + 20, 4), size = try n(cursor + 24, 4), method = try n(cursor + 10, 2), local = try n(cursor + 42, 4), crc = try n(cursor + 16, 4)
                guard size <= 1024 * 1024, packed <= 2 * 1024 * 1024, try n(local, 4) == 0x04034b50 else { throw PanelError(message: W("Plugin metadata is too large or corrupted.")) }
                let offset = try local + 30 + n(local + 26, 2) + n(local + 28, 2)
                guard offset >= 0 && offset + packed <= data.count else { throw PanelError(message: W("Truncated plugin file.")) }
                let compressed = Data(data[offset..<offset + packed]); let content: Data
                if method == 0 { content = compressed } else if method == 8 { content = try BinaryCodec.inflateData(compressed, window: -15, limit: 1024 * 1024) } else { throw PanelError(message: W("Unsupported ZIP compression.")) }
                let actual = content.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(content.count)) }
                guard content.count == size, actual == uLong(crc), let text = String(data: content, encoding: .utf8) else { throw PanelError(message: W("Invalid plugin checksum or YAML character encoding.")) }; descriptors[name] = text
            }
            cursor += 46 + nameCount + extra + comment
        }
        return descriptors
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
struct PluginUpdateCandidate: Identifiable {
    let id = UUID()
    let filename: String
    let file: URL
    let installed: PluginDescriptor
    let next: PluginDescriptor
    let originalHash: String
    let report: String
    var updateFilename: String { next.versionedFilename }
}

/// Paper matches updates by the exact descriptor name and adopts the staged filename.
enum PluginUpdatePlan {
    static func directory(_ config: String) throws -> String {
        let field = ConfigurationField.parse(config, properties: false).first { $0.path == "settings › update-folder" || $0.path == "update-folder" }
        if field == nil && config.range(of: #"(?m)^\s*update-folder\s*:"#, options: .regularExpression) != nil {
            throw PanelError(message: W("Cannot unambiguously read update-folder in bukkit.yml. Use the text editor."))
        }
        let update = field?.value ?? "update"
        let parts = update.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !update.hasPrefix("/"), !update.contains("\\"), !parts.isEmpty,
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }), !update.contains("\n"), !update.contains("\r") else {
            throw PanelError(message: W("Unsupported update-folder in bukkit.yml. Use the file manager."))
        }
        return "/plugins/" + parts.joined(separator: "/")
    }
    static func checkFilename(_ target: String, installed: String, files: [String]) throws {
        guard !files.contains(where: { $0 != installed && $0.caseInsensitiveCompare(target) == .orderedSame }) else {
            throw PanelError(message: W("Target file \(target) already exists in /plugins. Review it in the file manager first; nothing will be overwritten."))
        }
    }
    static func checkPending(_ pending: PluginDescriptor, next: PluginDescriptor) throws {
        guard pending.name != next.name else { throw PanelError(message: W("Version \(pending.version) is already staged for \(next.name). Remove the previous update JAR first so Paper finds only one update.")) }
    }
}

