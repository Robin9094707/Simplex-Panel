import SwiftUI

struct ModsView: View {
    let api: PanelAPI
    let server: Server
    @State private var entries: [JSON] = []
    @State private var descriptors: [String: ModDescriptor] = [:]
    @State private var errors: [String: String] = [:]
    @State private var error: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var loaded = false
    @State private var importer = false
    @State private var selected: JSON?
    @State private var imported: URL?
    @State private var candidate: ModCandidate?
    @State private var detail: ModDetail?
    @State private var toggleFile: String?
    @State private var staging: URL?
    var jars: [JSON] { entries.filter { $0["is_file"].bool && ($0["name"].string.hasSuffix(".jar") || $0["name"].string.hasSuffix(".jar.disabled")) }.sorted { $0["name"].string.localizedStandardCompare($1["name"].string) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                Label("Minecraft Java Mods", systemImage: "shippingbox.fill").font(.title2.bold()).foregroundStyle(Color.panelAccent)
                Text(W("Fabric, Quilt, Forge and NeoForge, including 1.20.1 and older or newer versions. Choose JARs matching your server, loader and dependencies. The app checks mod IDs, loader and version before updating. Changes require an offline server.")).font(.footnote).foregroundStyle(.secondary)
                Button(W("Install / upload new mod"), systemImage: "plus.circle") { selected = nil; importer = true }.requiresAccess(api, server.id, "file.create")
                NavigationLink(W("All mod files")) { FilesView(api: api, server: server, root: "/mods") }
                NavigationLink(W("Backed-up mod versions")) { FilesView(api: api, server: server, root: "/simplex-mod-backups") }
                Text(W("To restore: stop the server, move the new JAR out of /mods and move the backed-up JAR back into /mods. Mod backups do not restore worlds or configurations.")).font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView(W("Checking / transferring mod …")) }
                if let notice { Label(notice, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Color.panelAccent).textSelection(.enabled) }
            }
            if !loaded { ProgressView(W("Loading mods …")) }
            if loaded && jars.isEmpty { Text(W("No mod JARs in /mods")).foregroundStyle(.secondary) }
            Section(W("Mod files · \(jars.count)")) {
                ForEach(jars, id: \.["name"].string) { entry in modRow(entry) }
            }
        }.panelScreen().navigationTitle("Mods").navigationBarTitleDisplayMode(.inline).disabled(busy).task { await load() }.refreshable { descriptors = [:]; errors = [:]; await load() }.errorAlert($error)
            .sheet(item: $detail) { value in NavigationStack { List { Section(value.value.name) { LabeledContent("Mod-IDs", value: value.value.ids.joined(separator: ", ")); LabeledContent("Version", value: value.value.version); LabeledContent("Loader", value: value.value.loader); LabeledContent("Minecraft", value: value.value.minecraft); LabeledContent(W("Environment"), value: value.value.environment) }; Section(W("Metadata")) { Text(value.value.metadata).font(.caption.monospaced()).textSelection(.enabled) } }.navigationTitle(W("Mod details")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { detail = nil } } } } }
            .sheet(isPresented: Binding(get: { toggleFile != nil }, set: { if !$0 { toggleFile = nil } })) {
                if let name = toggleFile {
                    ActionForm(title: name.hasSuffix(".disabled") ? W("Enable mod") : W("Disable mod"), detail: W("The server must be offline. Dependent mods may require this mod. Changes apply on the next start."), fields: [], destructive: true, submit: W("Confirm")) { _ in
                        try await ModInstaller.stopped(api, server: server.id)
                        let target = name.hasSuffix(".disabled") ? String(name.dropLast(".disabled".count)) : name + ".disabled"
                        let rows = try await api.list("servers/\(server.id)/files/list", query: ["directory": "/mods"])
                        guard !rows.contains(where: { $0["name"].string.caseInsensitiveCompare(target) == .orderedSame }) else { throw PanelError(message: W("Target file already exists. Nothing will be overwritten.")) }
                        try await api.mutate("servers/\(server.id)/files/rename", method: "PUT", ["root": "/mods", "files": [["from": name, "to": target]]])
                        descriptors = [:]; await load()
                    }
                }
            }
            .sheet(isPresented: $importer, onDismiss: { if let imported { self.imported = nil; inspect(imported) } }) {
                FileImportPicker { result in switch result { case .success(let urls): imported = urls.first; case .failure(let failure): error = failure.localizedDescription }; importer = false }.ignoresSafeArea()
            }
            .sheet(item: $candidate, onDismiss: { if let staging { try? FileManager.default.removeItem(at: staging) }; staging = nil }) { value in
                ActionForm(title: value.installed == nil ? W("Install mod") : W("Update mod"), detail: W("\(value.next.name)\nIDs: \(value.next.ids.joined(separator: ", "))\nLoader: \(value.next.loader)\nInstalled: \(value.installed?.version ?? "–")\nNew version: \(value.next.version)\nMinecraft: \(value.next.minecraft)\n\nExisting mod IDs and the upload checksum are checked. The previous JAR is backed up outside /mods. Metadata checks do not guarantee full runtime compatibility."), fields: [Field(key: "ack", label: W("Minecraft version, loader and dependencies match"), value: "false", kind: .toggle)], submit: W("Install verified file")) { values in
                    guard values["ack"]?.bool == true else { throw PanelError(message: W("Confirm compatibility first.")) }
                    busy = true; defer { busy = false }
                    notice = try await ModInstaller.install(value, api: api, server: server.id)
                    descriptors = [:]; await load(); Feedback.success()
                }
            }
    }
    func modRow(_ entry: JSON) -> some View {
        let name = entry["name"].string, descriptor = descriptors[name]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor?.name ?? name).font(.headline)
                    Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(W("Read details & version"), systemImage: "info.circle") { Task { await metadata(entry); if let value = descriptors[name] { detail = ModDetail(value: value) } } }.requiresAccess(api, server.id, "file.read-content")
                    if !name.hasSuffix(".disabled") { Button(W("Upload update file"), systemImage: "arrow.up.doc") { selected = entry; importer = true }.requiresAccess(api, server.id, "file.update") }
                    Button(name.hasSuffix(".disabled") ? W("Enable") : W("Disable"), systemImage: "power") { toggle(name) }.requiresAccess(api, server.id, "file.update")
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
            if let descriptor { Text("\(descriptor.loader) · \(descriptor.version) · MC \(descriptor.minecraft)").font(.caption).foregroundStyle(Color.panelAccent) }
            else if let problem = errors[name] { Text(problem).font(.caption).foregroundStyle(.orange) }
            else { Text(W("Load metadata via Details · ") + bytes(entry["size"].double)).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
    func load() async {
        do {
            let root = try await api.list("servers/\(server.id)/files/list", query: ["directory": "/"])
            if root.contains(where: { $0["name"].string == "mods" && !$0["is_file"].bool }) { entries = try await api.list("servers/\(server.id)/files/list", query: ["directory": "/mods"]) } else { entries = [] }
            loaded = true
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func metadata(_ entry: JSON) async {
        let name = entry["name"].string
        guard descriptors[name] == nil else { return }; busy = true; defer { busy = false }
        do { let data = try await api.fileData(server: server.id, path: "/mods/" + name, limit: 128 * 1024 * 1024); descriptors[name] = try await Task.detached { try ModArchive.descriptor(data) }.value; errors[name] = nil }
        catch { errors[name] = error.localizedDescription }
    }
    func toggle(_ name: String) { toggleFile = name }
    func inspect(_ url: URL) {
        busy = true; notice = nil
        Task { defer { busy = false; let folder = url.deletingLastPathComponent(); if folder.lastPathComponent.hasPrefix("addon-") || folder.lastPathComponent.hasPrefix("market-") { try? FileManager.default.removeItem(at: folder) } }; do {
            guard !api.demo else { throw PanelError(message: W("Mods are read only in demo mode.")) }
            guard url.pathExtension.lowercased() == "jar" else { throw PanelError(message: W("Choose a single mod JAR.")) }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let resource = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resource.isRegularFile == true, (resource.fileSize ?? 0) <= 128 * 1024 * 1024 else { throw PanelError(message: W("Only JAR files up to 128 MiB are supported.")) }
            let bytes = try await Task.detached { try Data(contentsOf: url) }.value
            let next = try await Task.detached { try ModArchive.descriptor(bytes) }.value
            guard next.environment != "client" else { throw PanelError(message: W("This mod is intended exclusively for clients.")) }
            var installed: ModDescriptor?, hash: String?
            if let selected {
                let data = try await api.fileData(server: server.id, path: "/mods/" + selected["name"].string, limit: 128 * 1024 * 1024)
                let old = try await Task.detached { try ModArchive.descriptor(data) }.value
                try old.validateUpdate(next); installed = old; hash = PluginArchive.digest(data)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(url.lastPathComponent); try bytes.write(to: file)
            staging = folder; candidate = ModCandidate(file: file, next: next, installed: installed, oldFilename: selected?["name"].string, oldHash: hash)
        } catch { self.error = error.localizedDescription } }
    }
}
struct ModDetail: Identifiable { let id = UUID(); let value: ModDescriptor }


