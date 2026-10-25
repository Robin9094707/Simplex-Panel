import SwiftUI
import UniformTypeIdentifiers

struct PluginsView: View {
    let api: PanelAPI
    let server: Server
    @State private var install = false
    @State private var entries: [JSON] = []
    @State private var pending: [JSON] = []
    @State private var updateDirectory = "/plugins/update"
    @State private var detail: PluginDetailSelection?
    @State private var refreshID = UUID()
    @State private var error: String?
    @State private var operation: Operation?
    @State private var importer = false
    @State private var selectedPlugin: String?
    @State private var importedPlugin: URL?
    @State private var candidate: PluginUpdateCandidate?
    @State private var stagedLocal: URL?
    @State private var busy = false
    @State private var message: String?
    var prefix: String { "servers/\(server.id)/files" }
    var jars: [JSON] { entries.filter { $0["is_file"].bool && ($0["name"].string.hasSuffix(".jar") || $0["name"].string.hasSuffix(".jar.disabled")) }.sorted { $0["name"].string.localizedStandardCompare($1["name"].string) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                Label(W("Paper plugins"), systemImage: "puzzlepiece.extension.fill").font(.title2.bold()).foregroundStyle(Color.panelAccent)
                Text(W("Stage new JAR versions in Paper's update folder. Paper applies them on the next restart. Select the installed plugin first. The app compares names, main classes and versions. You must also check runtime compatibility and dependencies.")).font(.footnote).foregroundStyle(.secondary)
                Button(W("Install new plugin"), systemImage: "plus.circle") { install = true }.requiresAccess(api, server.id, "file.create")
                Text(W("Choose Upload update file on the plugin below.")).font(.footnote).foregroundStyle(.secondary)
                if busy { ProgressView(W("Transferring update …")) }
                if let message { Label(message, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Color.panelAccent) }
                NavigationLink(W("Plugin files & configurations")) { FilesView(api: api, server: server, root: "/plugins") }
                NavigationLink(W("Staged updates")) { FilesView(api: api, server: server, root: updateDirectory) }
                Link(W("Paper plugin update guide"), destination: URL(string: "https://docs.papermc.io/paper/updating/#step-2-update-plugins")!)
            } footer: { Text(W("The update path is read from bukkit.yml. Default: /plugins/update. Install new plugins in /plugins while the server is offline.")) }
            Section {
                ForEach(jars, id: \.["name"].string) { entry in
                    let name = entry["name"].string
                    PluginListRow(api: api, server: server, entry: entry, pending: pending, updateDirectory: updateDirectory, refreshID: refreshID, busy: busy, details: {
                        detail = PluginDetailSelection(entry: entry)
                    }, update: { selectedPlugin = name; importer = true }, toggle: { rename(name) }, remove: {
                        operation = Operation(title: W("Delete plugin"), detail: W("\(name) will be permanently deleted. Stop the server first. The configuration folder is preserved."), path: prefix + "/delete", fixed: ["root": .string("/plugins"), "files": .array([.string(name)])], destructive: true, submit: W("Delete JAR"), stoppedServer: server.id)
                    }, catalog: api.plugins)
                }
            } header: { Text(W("JAR files · \(jars.count)")) } footer: { Text(W("Versions are read from server JARs, not guessed from filenames. Visible JARs up to 8 MiB are read automatically; larger ones when opening Details. Loaded plugins may run a different version until restart.")) }
        }.panelScreen().navigationTitle("Plugins").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { api.plugins.clear(server: server.id); await load(); refreshID = UUID() }.errorAlert($error)
            .sheet(isPresented: $install) { PluginInstallView(api: api, server: server) { Task { await load() } } }
            .sheet(item: $detail) { PluginDetailsView(api: api, server: server, entry: $0.entry, catalog: api.plugins) }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
            .sheet(item: $candidate, onDismiss: { if let url = stagedLocal { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }; stagedLocal = nil }) { value in
                ActionForm(title: W("Review plugin update"), detail: W("\(value.installed.name)\nInstalled: \(value.installed.version)\nNew file: \(value.next.version)\nUpdate filename: \(value.updateFilename)\nAPI version: \(value.next.apiVersion)\n\n\(value.report)\n\nVerification does not guarantee full Minecraft/Java compatibility. The update is applied on the next server start."), fields: [Field(key: "ack", label: W("Compatible server version and dependencies checked"), value: "false", kind: .toggle)], submit: W("Stage update")) { values in
                    guard values["ack"]?.bool == true else { throw PanelError(message: W("Confirm the compatibility check first.")) }
                    try await commit(value)
                }
            }
            .sheet(isPresented: $importer, onDismiss: {
                if let url = importedPlugin { importedPlugin = nil; inspect(url) }
            }) {
                FileImportPicker { result in
                    switch result { case .success(let urls): importedPlugin = urls.first; case .failure(let e): error = e.localizedDescription }
                    importer = false
                }.ignoresSafeArea()
            }
    }
    func load() async {
        do {
            entries = try await api.list(prefix + "/list", query: ["directory": "/plugins"])
            if let config = try? await api.fileText(server: server.id, path: "/bukkit.yml"), let directory = try? PluginUpdatePlan.directory(config) { updateDirectory = directory }
            pending = (try? await api.list(prefix + "/list", query: ["directory": updateDirectory]))?.filter { $0["is_file"].bool && $0["name"].string.hasSuffix(".jar") } ?? []
            for entry in pending where entry["size"].double <= 8 * 1024 * 1024 {
                await api.plugins.load(api: api, server: server.id, directory: updateDirectory, entry: entry)
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func rename(_ name: String) {
        let target = name.hasSuffix(".disabled") ? String(name.dropLast(".disabled".count)) : name + ".disabled"
        operation = Operation(title: name.hasSuffix(".disabled") ? W("Enable plugin") : W("Disable plugin"), detail: W("Stop the server first. Changes apply on the next start. Configurations are not deleted."), path: prefix + "/rename", method: "PUT", fixed: ["root": .string("/plugins"), "files": .array([.object(["from": .string(name), "to": .string(target)])])], destructive: true, stoppedServer: server.id)
    }
    func inspect(_ url: URL) {
        guard url.pathExtension.lowercased() == "jar", let filename = selectedPlugin else { error = W("Select the installed plugin first, then a JAR."); return }
        busy = true; message = nil
        Task { defer { busy = false; let folder = url.deletingLastPathComponent(); if folder.lastPathComponent.hasPrefix("addon-") || folder.lastPathComponent.hasPrefix("market-") { try? FileManager.default.removeItem(at: folder) } }; do {
            guard !api.demo else { throw PanelError(message: W("Updates are disabled in demo mode.")) }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let installedData = try await api.fileData(server: server.id, path: "/plugins/" + filename, limit: 128 * 1024 * 1024)
            let result = try await Task.detached(priority: .userInitiated) {
                let resource = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard resource.isRegularFile == true else { throw PanelError(message: W("Select one JAR file, not a folder.")) }
                let size = resource.fileSize ?? 0
                guard size <= 128 * 1024 * 1024 else { throw PanelError(message: W("JAR exceeds 128 MiB.")) }
                let nextData = try Data(contentsOf: url)
                let old = try PluginArchive.descriptor(installedData), next = try PluginArchive.descriptor(nextData)
                let report = try old.validateUpdate(next)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let local = folder.appendingPathComponent(next.versionedFilename); try nextData.write(to: local)
                return PluginUpdateCandidate(filename: filename, file: local, installed: old, next: next, originalHash: PluginArchive.digest(installedData), report: report)
            }.value
            candidate = result; stagedLocal = result.file
        } catch { self.error = error.localizedDescription } }
    }
    func commit(_ value: PluginUpdateCandidate) async throws {
        busy = true; defer { busy = false }
        let current = try await api.fileData(server: server.id, path: "/plugins/" + value.filename, limit: 128 * 1024 * 1024)
        guard PluginArchive.digest(current) == value.originalHash else { throw PanelError(message: W("The installed plugin has changed. Select it again.")) }
        let config = try await api.fileText(server: server.id, path: "/bukkit.yml")
        let targetDirectory = try PluginUpdatePlan.directory(config)
        let components = targetDirectory.dropFirst("/plugins/".count).split(separator: "/").map(String.init)
        let installedFiles = try await api.list(prefix + "/list", query: ["directory": "/plugins"])
        try PluginUpdatePlan.checkFilename(value.updateFilename, installed: value.filename, files: installedFiles.map { $0["name"].string })
        var directory = "/plugins"
        for part in components {
            let entries = try await api.list(prefix + "/list", query: ["directory": directory])
            if !entries.contains(where: { $0["name"].string == part && !$0["is_file"].bool }) { try await api.mutate(prefix + "/create-folder", ["root": directory, "name": part]) }
            directory = pathJoin(directory, part)
        }
        let staged = try await api.list(prefix + "/list", query: ["directory": directory])
        guard !staged.contains(where: { $0["name"].string.caseInsensitiveCompare(value.updateFilename) == .orderedSame }) else { throw PanelError(message: W("An update is already staged for this plugin. Remove the previous update file in the file manager first.")) }
        // Different versioned filenames must not stage two candidates for one plugin.
        for entry in staged where entry["is_file"].bool && entry["name"].string.hasSuffix(".jar") {
            let data = try await api.fileData(server: server.id, path: pathJoin(directory, entry["name"].string), limit: 128 * 1024 * 1024)
            let pending = try await Task.detached(priority: .utility) { try PluginArchive.descriptor(data) }.value
            try PluginUpdatePlan.checkPending(pending, next: value.next)
        }
        try await api.upload(server: server.id, directory: directory, file: value.file)
        let uploaded = try await api.fileData(server: server.id, path: pathJoin(directory, value.updateFilename), limit: 128 * 1024 * 1024)
        let local = try Data(contentsOf: value.file, options: .mappedIfSafe)
        guard PluginArchive.digest(uploaded) == PluginArchive.digest(local) else { throw PanelError(message: W("Upload checksum mismatch. Remove the staged file before restarting.")) }
        await load()
        if let entry = pending.first(where: { $0["name"].string == value.updateFilename }) {
            api.plugins.rememberVerifiedUpload(value.next, server: server.id, directory: directory, entry: entry)
        }
        message = W("\(value.updateFilename) verified and uploaded to \(directory). Paper will apply it on the next start if compatible.")
        Feedback.success()
    }
}


