import Foundation

struct ModDescriptor: Equatable, Sendable {
    let ids: [String]
    let name: String
    let version: String
    let loader: String
    let minecraft: String
    let environment: String
    let metadata: String
    func validateUpdate(_ next: ModDescriptor) throws {
        guard ids == next.ids, loader == next.loader else { throw PanelError(message: W("Wrong mod update file. Expected: \(ids.joined(separator: ", ")) (\(loader)); selected: \(next.ids.joined(separator: ", ")) (\(next.loader)).")) }
        guard version != next.version else { throw PanelError(message: W("This mod version is already installed: ") + version) }
        if version.range(of: #"^\d+(\.\d+){0,4}$"#, options: .regularExpression) != nil,
           next.version.range(of: #"^\d+(\.\d+){0,4}$"#, options: .regularExpression) != nil,
           next.version.compare(version, options: .numeric) != .orderedDescending { throw PanelError(message: W("This file does not contain a newer mod version.")) }
        guard next.environment != "client" else { throw PanelError(message: W("This mod is only intended for the Minecraft client.")) }
    }
}
enum ModArchive {
    static let files: Set<String> = ["fabric.mod.json", "quilt.mod.json", "META-INF/mods.toml", "META-INF/neoforge.mods.toml", "mcmod.info", "META-INF/MANIFEST.MF"]
    static func descriptor(_ data: Data) throws -> ModDescriptor { try parse(PluginArchive.metadata(data, names: files)) }
    static func parse(_ files: [String: String]) throws -> ModDescriptor {
        func result(ids: [String], name: String, version: String, loader: String, minecraft: String = W("Not specified"), environment: String = "*", raw: String) throws -> ModDescriptor {
            let unique = Array(Set(ids)).sorted()
            guard !unique.isEmpty, unique.allSatisfy({ $0.range(of: #"^[A-Za-z0-9_.-]{1,128}$"#, options: .regularExpression) != nil }), !version.isEmpty, !version.contains("${"), version.utf8.count < 512 else { throw PanelError(message: W("Mod ID or version is missing or cannot be read unambiguously. Use the file manager for this JAR.")) }
            return ModDescriptor(ids: unique, name: name.isEmpty ? unique.joined(separator: ", ") : String(name.prefix(512)), version: version, loader: loader, minecraft: minecraft, environment: environment, metadata: String(raw.prefix(200_000)))
        }
        // Hybrid jars may contain multiple loader descriptors. Use their canonical loader metadata.
        if let text = files["quilt.mod.json"] {
            let json = try JSON.parse(text), q = json["quilt_loader"], mc = q["depends"].array.first { $0["id"].string == "minecraft" }?["versions"] ?? .null
            return try result(ids: [q["id"].string], name: q["metadata"]["name"].string, version: q["version"].string, loader: "Quilt", minecraft: mc.string.isEmpty ? mc.pretty : mc.string, environment: json["minecraft"]["environment"].string, raw: text)
        }
        if let text = files["fabric.mod.json"] {
            let json = try JSON.parse(text), mc = json["depends"]["minecraft"]
            return try result(ids: [json["id"].string], name: json["name"].string, version: json["version"].string, loader: "Fabric", minecraft: mc == .null ? W("Not specified") : mc.string.isEmpty ? mc.pretty : mc.string, environment: json["environment"].string, raw: text)
        }
        for file in ["META-INF/neoforge.mods.toml", "META-INF/mods.toml"] {
            if let text = files[file] {
                // Only [[mods]] contributes identity, never dependency modId fields.
                var section = "", mods: [[String: String]] = [], minecraft = W("Not specified"), dependency: [String: String] = [:]
                func finishDependency() { if dependency["modId"] == "minecraft" { minecraft = dependency["versionRange"] ?? minecraft } }
                for raw in text.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("[") {
                        finishDependency(); dependency = [:]; section = line
                        if line == "[[mods]]" { mods.append([:]) }; continue
                    }
                    guard let eq = line.firstIndex(of: "=") else { continue }
                    let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    guard value.hasPrefix("\"") || value.hasPrefix("'") else { continue }
                    let quote = value.first!; let content = value.dropFirst().prefix { $0 != quote }
                    if section == "[[mods]]", !mods.isEmpty { mods[mods.count - 1][key] = String(content) }
                    if section.hasPrefix("[[dependencies.") { dependency[key] = String(content) }
                }
                finishDependency()
                let manifestVersion = files["META-INF/MANIFEST.MF"]?.components(separatedBy: .newlines).first { $0.hasPrefix("Implementation-Version:") }.map { String($0.dropFirst("Implementation-Version:".count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let versions = mods.map { ($0["version"] ?? "").replacingOccurrences(of: "${file.jarVersion}", with: manifestVersion) }
                guard Set(versions).count == 1 else { throw PanelError(message: W("The mod JAR contains multiple different version values. Use the file manager.")) }
                return try result(ids: mods.map { $0["modId"] ?? "" }, name: mods.compactMap { $0["displayName"] }.joined(separator: ", "), version: versions.first ?? "", loader: file.contains("neoforge") ? "NeoForge" : "Forge", minecraft: minecraft, raw: text)
            }
        }
        if let text = files["mcmod.info"] {
            let json = try JSON.parse(text), mods = json.array.isEmpty ? json["modList"].array : json.array
            let versions = Set(mods.map { $0["version"].string })
            guard versions.count == 1 else { throw PanelError(message: W("Ambiguous legacy mod version.")) }
            return try result(ids: mods.map { $0["modid"].string }, name: mods.map { $0["name"].string }.joined(separator: ", "), version: versions.first ?? "", loader: "Forge", minecraft: mods.first?["mcversion"].string ?? W("Not specified"), raw: text)
        }
        throw PanelError(message: W("No supported mod metadata found. Supported: Fabric, Quilt, Forge, NeoForge and older Forge JARs with mcmod.info. Plugins belong in /plugins."))
    }
}
struct ModCandidate: Identifiable {
    let id = UUID()
    let file: URL
    let next: ModDescriptor
    let installed: ModDescriptor?
    let oldFilename: String?
    let oldHash: String?
}
@MainActor enum ModInstaller {
    static func stopped(_ api: PanelAPI, server: String) async throws {
        let state = try await api.request("servers/\(server)/resources").attributes["current_state"].string
        guard state == "offline" else { throw PanelError(message: W("Stop the Minecraft server first. JAR files can only be changed while the server is offline.")) }
    }
    static func ensureFolder(_ api: PanelAPI, server: String, root: String, name: String) async throws {
        let rows = try await api.list("servers/\(server)/files/list", query: ["directory": root])
        if let row = rows.first(where: { $0["name"].string == name }) {
            guard !row["is_file"].bool else { throw PanelError(message: W("A file occupies a required folder path: ") + name) }
        } else { try await api.mutate("servers/\(server)/files/create-folder", ["root": root, "name": name]) }
    }
    static func move(_ api: PanelAPI, server: String, from: String, to: String) async throws {
        try await api.mutate("servers/\(server)/files/rename", method: "PUT", ["root": "/", "files": [["from": String(from.drop(while: { $0 == "/" })), "to": String(to.drop(while: { $0 == "/" }))]]])
    }
    static func install(_ candidate: ModCandidate, api: PanelAPI, server: String) async throws -> String {
        try await stopped(api, server: server)
        let prefix = "servers/\(server)/files"
        try await ensureFolder(api, server: server, root: "/", name: "mods")
        let rows = try await api.list(prefix + "/list", query: ["directory": "/mods"])
        let target = candidate.file.lastPathComponent
        guard !rows.contains(where: { $0["name"].string.caseInsensitiveCompare(target) == .orderedSame && $0["name"].string != candidate.oldFilename }) else { throw PanelError(message: W("A different file with this name already exists in the mods folder.")) }
        // Detect duplicates by mod IDs, not filenames. Unknown jars require manual review.
        for row in rows where row["is_file"].bool && row["name"].string.hasSuffix(".jar") && row["name"].string != candidate.oldFilename {
            let data = try await api.fileData(server: server, path: "/mods/" + row["name"].string, limit: 128 * 1024 * 1024)
            let descriptor = try await Task.detached { try ModArchive.descriptor(data) }.value
            guard Set(descriptor.ids).isDisjoint(with: candidate.next.ids) else { throw PanelError(message: W("This mod is already installed: \(descriptor.name). Choose Upload update file for it.")) }
        }
        if let old = candidate.oldFilename, let hash = candidate.oldHash {
            let data = try await api.fileData(server: server, path: "/mods/" + old, limit: 128 * 1024 * 1024)
            guard PluginArchive.digest(data) == hash else { throw PanelError(message: W("The installed mod has changed. Select it again.")) }
        }
        try await ensureFolder(api, server: server, root: "/", name: "simplex-mod-staging")
        let transaction = UUID().uuidString
        try await ensureFolder(api, server: server, root: "/simplex-mod-staging", name: transaction)
        let stage = "/simplex-mod-staging/" + transaction
        try await api.upload(server: server, directory: stage, file: candidate.file)
        let uploaded = try await api.fileData(server: server, path: pathJoin(stage, target), limit: 128 * 1024 * 1024)
        let local = try Data(contentsOf: candidate.file, options: .mappedIfSafe)
        guard PluginArchive.digest(uploaded) == PluginArchive.digest(local) else { throw PanelError(message: W("Upload checksum mismatch. Installed mods were not changed.")) }
        try await stopped(api, server: server)
        var backup: String?
        if let old = candidate.oldFilename {
            try await ensureFolder(api, server: server, root: "/", name: "simplex-mod-backups")
            try await ensureFolder(api, server: server, root: "/simplex-mod-backups", name: transaction)
            let saved = "/simplex-mod-backups/" + transaction + "/" + old
            try await move(api, server: server, from: "/mods/" + old, to: saved); backup = saved
        }
        do { try await move(api, server: server, from: pathJoin(stage, target), to: "/mods/" + target) }
        catch {
            if let backup, let old = candidate.oldFilename {
                do { try await move(api, server: server, from: backup, to: "/mods/" + old) }
                catch { throw PanelError(message: W("Installation interrupted. The previous mod is at \(backup). Move it back to /mods in the file manager before starting the server.")) }
            }
            throw error
        }
        return backup.map { W("Mod installed. Previous JAR backed up at ") + $0 } ?? W("Mod installed. It will load the next time the server starts.")
    }
}

