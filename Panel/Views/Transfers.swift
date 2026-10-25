import SwiftUI

struct TransfersView: View {
    @ObservedObject private var manager = TransferManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @AppStorage("transferActivities") private var activities = true
    @State private var share: ShareItem?
    @State private var error: String?
    @State private var removing: TransferRecord?
    @State private var cancelling: TransferRecord?
    @State private var clearing = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Live Activities & Dynamic Island", isOn: $activities)
                    Text(W("Transfers continue in the iOS background when possible. Force quitting may stop them. Download resumption depends on the file server and download link validity. Select uploads again if needed; your provider may not support resuming at the last byte.")).font(.footnote).foregroundStyle(.secondary)
                }
                if let issue = manager.storageError { Section { Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
                if manager.records.isEmpty { ContentUnavailableView(W("All transferred"), systemImage: "arrow.up.arrow.down.circle", description: Text(W("New uploads and downloads appear here with their actual progress."))) }
                ForEach(manager.records) { record in
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: record.upload ? "arrow.up.doc.fill" : "arrow.down.doc.fill").font(.title2).foregroundStyle(Color.panelAccent)
                                VStack(alignment: .leading, spacing: 4) { Text(record.filename).font(.headline).textSelection(.enabled); Text(record.context).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if record.state == "completed" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            if record.active {
                                if let fraction = record.fraction { ProgressView(value: fraction).tint(Color.panelAccent) }
                                else { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                            }
                            HStack { Text(record.title); Spacer(); Text(progress(record)).monospacedDigit() }.font(.caption).foregroundStyle(record.state == "failed" ? Color.orange : .secondary)
                            if let issue = record.issue { Text(issue).font(.footnote).foregroundStyle(.orange).textSelection(.enabled) }
                            HStack {
                                if record.active {
                                    if !record.upload && record.state == "running" { Button("Pause", systemImage: "pause") { manager.pause(record) } }
                                    Button(W("Cancel"), systemImage: "xmark", role: .destructive) { cancelling = record }
                                } else {
                                    if !record.upload && record.state != "completed" {
                                        Button(W("Resume"), systemImage: "play") { resume(record) }
                                        if manager.hasResume(record) { Button(W("Reload"), systemImage: "arrow.clockwise") { resume(record, restart: true) } }
                                        if !manager.hasResume(record) { Text(W("No byte resumption: starts again at 0%.")).font(.caption2).foregroundStyle(.secondary) }
                                    }
                                    if record.state == "completed" && !record.upload { Button(W("Save to Files / share"), systemImage: "square.and.arrow.up") { share = ShareItem(url: manager.localFile(record)) } }
                                    Spacer(); Button(W("Remove"), systemImage: "trash", role: .destructive) { removing = record }.labelStyle(.iconOnly)
                                }
                            }.buttonStyle(.borderless)
                            if !record.active && record.state != "completed" { Text(record.upload ? W("Select the file again to upload to the target folder. First check for an incomplete file on the server.") : W("If resuming fails, start the download again from the file manager to request a new link.")).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 6)
                    }
                }
            }.panelScreen().navigationTitle(W("Transfers")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button(W("Clear all"), systemImage: "trash", role: .destructive) { clearing = true }.disabled(manager.records.isEmpty) }; ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { dismiss() } } }
                .confirmationDialog(W("Clear transfers?"), isPresented: $clearing, titleVisibility: .visible) {
                    Button(W("Clear history · keep active transfers"), role: .destructive) { manager.clearAll() }
                    if manager.records.contains(where: \.active) { Button(W("Cancel all and clear"), role: .destructive) { manager.clearAll(includingActive: true) } }
                } message: { Text(W("Downloaded files on this iPhone will be removed. Server files remain. A canceled upload may leave an incomplete file on the server.")) }
                .sheet(item: $share) { ShareSheet(url: $0.url) }.errorAlert($error)
                .confirmationDialog(W("Remove the local transfer and saved file?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) { Button(W("Remove locally"), role: .destructive) { if let removing { manager.remove(removing) }; removing = nil } }
                .confirmationDialog(W("Cancel transfer?"), isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) { Button(W("Cancel"), role: .destructive) { if let cancelling { manager.cancel(cancelling) }; cancelling = nil } } message: { Text(W("A canceled upload may leave an incomplete file on the server.")) }
        }
    }
    func resume(_ record: TransferRecord, restart: Bool = false) {
        Task { do {
            let source = store.api.flatMap { DownloadSource.legacy(context: record.context, filename: record.filename, api: $0, servers: store.servers) }
            try await manager.resume(record, api: store.api, legacySource: source, restart: restart)
        } catch { self.error = error.localizedDescription } }
    }
    func progress(_ r: TransferRecord) -> String {
        let amount = bytes(Double(r.completed)) + (r.total > 0 ? " / " + bytes(Double(r.total)) : "")
        return amount + (r.fraction.map { " · \(Int($0 * 100)) %" } ?? "")
    }
}

struct TransferLink: View {
    @ObservedObject private var manager = TransferManager.shared
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            HStack {
                Label(W("Transfers"), systemImage: "arrow.up.arrow.down.circle")
                Spacer()
                if let record = manager.records.first(where: \.active) {
                    if let fraction = record.fraction { ProgressView(value: fraction).frame(width: 65) }
                    else { ProgressView() }
                    Text("\(manager.records.filter(\.active).count)").font(.caption).monospacedDigit()
                }
            }
        }.sheet(isPresented: $show) { TransfersView() }
    }
}


