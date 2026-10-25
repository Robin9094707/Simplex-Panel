import SwiftUI

struct PluginDetailSelection: Identifiable { let id = UUID(); let entry: JSON }
struct PluginDetailsView: View {
    let api: PanelAPI
    let server: Server
    let entry: JSON
    @ObservedObject var catalog: PluginCatalog
    @Environment(\.dismiss) private var dismiss
    var key: String { PluginCatalog.key(server: server.id, directory: "/plugins", entry: entry) }
    var descriptor: PluginDescriptor? { catalog.descriptor(server: server.id, entry: entry) }
    var body: some View {
        NavigationStack {
            AccessBoundary(access: api.access, server: server.id, permission: "file.read-content") {
                Form {
                    Section {
                        Label(descriptor?.name ?? entry["name"].string, systemImage: "puzzlepiece.extension.fill").font(.title2.bold()).foregroundStyle(Color.panelAccent)
                        if let descriptor { LabeledContent(W("Version on server"), value: descriptor.version).font(.headline) }
                        else if catalog.loading.contains(key) { ProgressView(W("Reading plugin JAR …")) }
                        else { Button(W("Read metadata again"), systemImage: "arrow.clockwise") { Task { await catalog.load(api: api, server: server.id, entry: entry, retry: true) } } }
                        if let error = catalog.errors[key] { Text(error).font(.footnote).foregroundStyle(.orange) }
                    } footer: { Text(W("Read from the JAR in /plugins. The running version may differ until the next server start.")) }
                    if let descriptor {
                        Section("Plugin") {
                            LabeledContent(W("Name"), value: descriptor.name).textSelection(.enabled)
                            LabeledContent("Version", value: descriptor.version).textSelection(.enabled)
                            LabeledContent(W("Minecraft API"), value: descriptor.apiVersion).textSelection(.enabled)
                            LabeledContent(W("Main class"), value: descriptor.main).font(.caption.monospaced()).textSelection(.enabled)
                            if !descriptor.author.isEmpty { LabeledContent(W("Author / authors"), value: descriptor.author).textSelection(.enabled) }
                            if !descriptor.summary.isEmpty { Text(descriptor.summary).textSelection(.enabled) }
                            if !descriptor.website.isEmpty { LabeledContent(W("Website"), value: descriptor.website).font(.caption).textSelection(.enabled) }
                        }
                        Section(W("Complete metadata")) {
                            NavigationLink {
                                SyntaxEditor(text: .constant(descriptor.rawYAML), colors: true, editable: false).panelScreen().navigationTitle(descriptor.descriptorFile).navigationBarTitleDisplayMode(.inline)
                            } label: { Label(descriptor.descriptorFile, systemImage: "doc.text") }
                            Button(W("Copy metadata"), systemImage: "doc.on.doc") { Clipboard.copy(descriptor.rawYAML) }
                        }
                    }
                    Section(W("File")) {
                        LabeledContent(W("Filename"), value: entry["name"].string).textSelection(.enabled)
                        LabeledContent(W("Size"), value: bytes(entry["size"].double))
                        if !entry["modified_at"].string.isEmpty { LabeledContent(W("Modified"), value: entry["modified_at"].string).font(.caption).textSelection(.enabled) }
                    }
                }.panelScreen()
            }.navigationTitle(W("Plugin details")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { dismiss() } } }
                .task { await catalog.load(api: api, server: server.id, entry: entry, retry: true) }
        }
    }
}
struct PluginListRow: View {
    let api: PanelAPI
    let server: Server
    let entry: JSON
    let pending: [JSON]
    let updateDirectory: String
    let refreshID: UUID
    let busy: Bool
    let details: () -> Void
    let update: () -> Void
    let toggle: () -> Void
    let remove: () -> Void
    @ObservedObject var catalog: PluginCatalog
    var name: String { entry["name"].string }
    var metadata: PluginDescriptor? { catalog.descriptor(server: server.id, entry: entry) }
    var pendingVersion: String? {
        guard let metadata else { return nil }
        return pending.compactMap { catalog.descriptor(server: server.id, directory: updateDirectory, entry: $0) }.first { $0.name == metadata.name }?.version
    }
    var key: String { PluginCatalog.key(server: server.id, directory: "/plugins", entry: entry) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "puzzlepiece.extension.fill").font(.title2).foregroundStyle(name.hasSuffix(".disabled") ? Color.secondary : Color.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text(metadata?.name ?? name).font(.headline).textSelection(.enabled)
                    if let metadata { Text("Version \(metadata.version)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.panelAccent).textSelection(.enabled) }
                    else if catalog.loading.contains(key) { Text(W("Reading version …")).font(.caption).foregroundStyle(.secondary) }
                    else { Text(W("Read version from JAR details")).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(W("Plugin details"), systemImage: "info.circle", action: details).labelStyle(.iconOnly).font(.title2).buttonStyle(.borderless).requiresAccess(api, server.id, "file.read-content").accessibilityIdentifier("pluginDetails-" + name)
            }
            Text(name).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text(bytes(entry["size"].double) + (name.hasSuffix(".disabled") ? W(" · Disabled") : W(" · JAR on server"))).font(.caption).foregroundStyle(.secondary)
            if let pendingVersion { Label(W("Update \(pendingVersion) staged · next start"), systemImage: "clock.arrow.circlepath").font(.caption.weight(.medium)).foregroundStyle(.orange) }
            if catalog.errors[key] != nil { Text(W("Metadata unavailable · open Details to retry")).font(.caption).foregroundStyle(.orange) }
            Button(W("Upload update file"), systemImage: "arrow.up.doc", action: update).buttonStyle(.borderless).disabled(busy || name.hasSuffix(".disabled")).requiresAccess(api, server.id, "file.create", "file.read-content")
            HStack {
                Button(name.hasSuffix(".disabled") ? W("Enable") : W("Disable"), action: toggle).requiresAccess(api, server.id, "file.update")
                Spacer()
                Button(W("Delete"), systemImage: "trash", role: .destructive, action: remove).requiresRequest(api, "servers/\(server.id)/files/delete")
            }.buttonStyle(.borderless).font(.subheadline)
        }.padding(.vertical, 7).task(id: refreshID) {
            // Avoid silently transferring a large Geyser/WorldEdit-sized JAR on scroll.
            if entry["size"].double <= 8 * 1024 * 1024 { await catalog.load(api: api, server: server.id, entry: entry) }
        }
    }
}

