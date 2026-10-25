import SwiftUI

struct BackupsView: View {
    let api: PanelAPI
    let server: Server
    @State private var backups: [JSON] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var operation: Operation?
    @State private var showTransfers = false
    @State private var share: ShareItem?
    @State private var downloading = false
    @State private var notice: String?
    var prefix: String { "servers/\(server.id)/backups" }
    var body: some View {
        List {
            Section {
                HStack {
                    Label("Backups", systemImage: "externaldrive.badge.timemachine").font(.headline)
                    Spacer(); Text("\(backups.count) / \(server.data["feature_limits"]["backups"].string)").monospacedDigit().foregroundStyle(.secondary)
                }
                Button(W("Create backup"), systemImage: "plus.circle.fill") { create() }.requiresAccess(api, server.id, "backup.create")
                if downloading { ProgressView(W("Requesting download link …")) }
                TransferLink()
            } footer: { Text(W("Your panel and provider manage backups. Successful completion is shown here.")) }
            if !loaded { ProgressView(W("Loading backups …")) }
            if loaded && backups.isEmpty { ContentUnavailableView(W("No backups yet"), systemImage: "externaldrive", description: Text(W("Create a backup before making major changes."))) }
            ForEach(Array(backups.enumerated()), id: \.offset) { _, backup in
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: backup["is_locked"].bool ? "lock.shield.fill" : "externaldrive.fill").font(.title2).foregroundStyle(Color.panelAccent)
                            VStack(alignment: .leading, spacing: 5) { Text(backup["name"].string).font(.headline); Text(backup["created_at"].string.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Menu { actions(backup) } label: { Image(systemName: "ellipsis.circle").font(.title3).padding(4) }
                        }
                        HStack {
                            Label(!BackupInfo(value: backup).completed ? W("Creating …") : BackupInfo(value: backup).successful ? W("Successful") : W("Failed"), systemImage: BackupInfo(value: backup).successful ? "checkmark.circle.fill" : !BackupInfo(value: backup).completed ? "clock" : "exclamationmark.circle").foregroundStyle(BackupInfo(value: backup).successful ? Color.green : Color.orange)
                            Spacer(); Text(bytes(backup["bytes"].double)).foregroundStyle(.secondary)
                        }.font(.caption)
                    }.padding(.vertical, 6)
                }
            }
        }.panelScreen().refreshable { await load() }
            .task {
                await load()
                while !Task.isCancelled { do { try await Task.sleep(for: .seconds(10)) } catch { break }; await load(silent: true) }
            }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .sheet(isPresented: $showTransfers) { TransfersView() }.errorAlert($error)
            .alert(W("Backup export"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK") { notice = nil } } message: { Text(notice ?? "") }

    }
    @ViewBuilder func actions(_ b: JSON) -> some View {
        let info = BackupInfo(value: b)
        let path = prefix + "/" + info.id
        if info.successful {
            Button(W("Download"), systemImage: "arrow.down.circle") { download(b) }.disabled(downloading || !info.downloadable || info.id.isEmpty).requiresRequest(api, path + "/download", method: "GET")
            Button(W("Restore"), systemImage: "arrow.counterclockwise", role: .destructive) {
                operation = Operation(title: W("Restore backup"), detail: W("Stop the server first. Files from this backup replace existing files. A current backup is recommended. Delete existing files first also removes files that are missing from the backup."), path: path + "/restore", fields: [Field(key: "truncate", label: W("Delete existing files first"), value: "false", kind: .toggle)], destructive: true, submit: W("Restore backup"))
            }.requiresAccess(api, server.id, "backup.restore")
        }
        Button(b["is_locked"].bool ? W("Unlock") : W("Protect from deletion"), systemImage: b["is_locked"].bool ? "lock.open" : "lock") { operation = Operation(title: b["is_locked"].bool ? W("Unlock backup") : W("Protect backup"), path: path + "/lock", submit: W("Confirm")) }.requiresRequest(api, path + "/lock", method: "POST")
        Button(W("Delete"), systemImage: "trash", role: .destructive) { operation = Operation(title: W("Delete backup"), detail: W("\(b["name"].string) will be permanently deleted."), path: path, method: "DELETE", destructive: true, submit: W("Delete permanently")) }.disabled(b["is_locked"].bool).requiresRequest(api, path, method: "DELETE")
    }
    func create() { operation = Operation(title: W("Create backup"), path: prefix, fields: [Field(key: "name", label: W("Name"), value: "Backup " + Date().formatted(date: .numeric, time: .shortened)), Field(key: "is_locked", label: W("Protect from deletion"), value: "false", kind: .toggle), Field(key: "ignored", label: W("Excluded files"), kind: .multiline, hint: W("Optional. One pattern per line, following your panel's backup rules."))], submit: W("Create")) }
    func load(silent: Bool = false) async { do { backups = try await api.list(prefix); loaded = true } catch is CancellationError {} catch { if !silent { self.error = error.localizedDescription } } }
    func download(_ backup: JSON) {
        downloading = true
        Task { defer { downloading = false }; do {
            guard !api.demo else { throw PanelError(message: W("Downloads are disabled in demo mode.")) }
            let info = BackupInfo(value: backup)
            guard !info.id.isEmpty, !info.id.contains("/") else { throw PanelError(message: W("The backup does not have a valid API ID.")) }
            let response = try await api.request(prefix + "/\(info.id)/download")
            let signed = try BackupInfo.downloadURL(response, base: api.base)
            let suffix = URL(string: signed)?.path.lowercased().hasSuffix(".zip") == true ? ".zip" : ".tar.gz"
            try TransferManager.shared.download(signed, filename: info.id + suffix, context: server.name + " · Backup", source: DownloadSource(panel: api.base.absoluteString, server: server.id, kind: "backup", resource: info.id))
            showTransfers = true
        } catch { self.error = error.localizedDescription } }
    }
}

