import SwiftUI

struct PluginInstallView: View {
    let api: PanelAPI
    let server: Server
    var installed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picker = false
    @State private var selected: URL?
    @State private var descriptor: PluginDescriptor?
    @State private var staged: URL?
    @State private var acknowledged = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(W("Choose a plugin JAR from your device. The app reads metadata and verifies the upload. The server must be offline.")).foregroundStyle(.secondary)
                    Button(W("Choose JAR"), systemImage: "doc.badge.plus") { picker = true }.disabled(busy)
                }
                if let descriptor {
                    Section("Plugin") {
                        LabeledContent(W("Name"), value: descriptor.name)
                        LabeledContent("Version", value: descriptor.version)
                        LabeledContent(W("API version"), value: descriptor.apiVersion)
                        Toggle(W("Server version and dependencies checked"), isOn: $acknowledged)
                        Button(W("Install plugin"), systemImage: "arrow.up.doc") { install() }.disabled(busy || !acknowledged)
                    }
                }
                if busy { ProgressView(W("Checking / transferring JAR …")) }
            }.panelScreen().navigationTitle(W("Install plugin")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(W("Cancel")) { dismiss() }.disabled(busy) } }.errorAlert($error).interactiveDismissDisabled(busy)
                .sheet(isPresented: $picker, onDismiss: { if let selected { self.selected = nil; inspect(selected) } }) {
                    FileImportPicker { result in
                        switch result { case .success(let urls): selected = urls.first; case .failure(let failure): error = failure.localizedDescription }
                        picker = false
                    }
                }
                .onDisappear { if let staged { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) } }
        }
    }
    func inspect(_ url: URL) {
        busy = true; descriptor = nil; acknowledged = false
        Task { defer { busy = false }; do {
            guard url.pathExtension.lowercased() == "jar" else { throw PanelError(message: W("Choose a plugin JAR.")) }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 128 * 1024 * 1024 else { throw PanelError(message: W("Only JAR files up to 128 MiB are supported.")) }
            let result = try await Task.detached(priority: .userInitiated) { () -> (PluginDescriptor, URL) in
                let data = try Data(contentsOf: url), metadata = try PluginArchive.descriptor(data)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent(metadata.versionedFilename); try data.write(to: file)
                return (metadata, file)
            }.value
            if let staged { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
            descriptor = result.0; staged = result.1
        } catch { self.error = error.localizedDescription } }
    }
    func install() {
        guard let descriptor, let staged else { return }; busy = true
        Task { defer { busy = false }; do {
            guard !api.demo else { throw PanelError(message: W("Uploads are disabled in demo mode.")) }
            try await ModInstaller.stopped(api, server: server.id)
            try await ModInstaller.ensureFolder(api, server: server.id, root: "/", name: "plugins")
            let rows = try await api.list("servers/\(server.id)/files/list", query: ["directory": "/plugins"])
            guard !rows.contains(where: { $0["name"].string.caseInsensitiveCompare(staged.lastPathComponent) == .orderedSame }) else { throw PanelError(message: W("Target file already exists. Nothing will be overwritten.")) }
            for row in rows where row["is_file"].bool && (row["name"].string.hasSuffix(".jar") || row["name"].string.hasSuffix(".jar.disabled")) {
                let data = try await api.fileData(server: server.id, path: pathJoin("/plugins", row["name"].string), limit: 128 * 1024 * 1024)
                let old = try await Task.detached { try PluginArchive.descriptor(data) }.value
                guard old.name.caseInsensitiveCompare(descriptor.name) != .orderedSame && old.main != descriptor.main else { throw PanelError(message: W("This plugin is already installed. Use the update feature.")) }
            }
            try await ModInstaller.ensureFolder(api, server: server.id, root: "/", name: "simplex-plugin-staging")
            let transaction = UUID().uuidString
            try await ModInstaller.ensureFolder(api, server: server.id, root: "/simplex-plugin-staging", name: transaction)
            let folder = "/simplex-plugin-staging/" + transaction
            try await api.upload(server: server.id, directory: folder, file: staged)
            let uploaded = try await api.fileData(server: server.id, path: pathJoin(folder, staged.lastPathComponent), limit: 128 * 1024 * 1024)
            let local = try Data(contentsOf: staged, options: .mappedIfSafe)
            guard PluginArchive.digest(uploaded) == PluginArchive.digest(local) else { throw PanelError(message: W("Upload checksum mismatch. Installed plugins were not changed.")) }
            try await ModInstaller.stopped(api, server: server.id)
            let latest = try await api.list("servers/\(server.id)/files/list", query: ["directory": "/plugins"])
            guard !latest.contains(where: { $0["name"].string.caseInsensitiveCompare(staged.lastPathComponent) == .orderedSame }) else { throw PanelError(message: W("Target file already exists. Nothing will be overwritten.")) }
            try await ModInstaller.move(api, server: server.id, from: pathJoin(folder, staged.lastPathComponent), to: pathJoin("/plugins", staged.lastPathComponent))
            api.plugins.clear(server: server.id); installed(); dismiss()
        } catch { self.error = error.localizedDescription } }
    }
}
