import SwiftUI
import WidgetKit

struct WidgetSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var records = WidgetStorage.servers()
    @State private var error: String?
    @State private var pending: Server?
    @State private var background = true
    @State private var busy = false
    @State private var report: String?
    var body: some View {
        List {
            Section(W("Connect widgets")) {
                Text(W("Choose server → Save widget access → Touch and hold the Home Screen → Add widget → Simplex Wing. Then select a server for configurable widgets.")).font(.footnote)
                Text(W("All servers · overview shows enabled servers without further selection. Use Online players · large list for names. Separate status, RAM, CPU and uptime widgets are also available.")).font(.footnote).foregroundStyle(.secondary)
                Text(WidgetStorage.connectionTitle).font(.caption).foregroundStyle(WidgetStorage.folder == nil ? .orange : .secondary).textSelection(.enabled)
                Text(W("iOS controls automatic refresh. The button in a widget requests new data; widgets do not refresh every second.")).font(.caption).foregroundStyle(.secondary)
                Button(W("Refresh widget data now"), systemImage: "arrow.clockwise") { Task { await refresh() } }.disabled(busy)
                if let report { Text(report).font(.caption).foregroundStyle(.secondary) }
                if busy { ProgressView() }
            }
            Section(W("Enabled servers · \(records.count)")) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(record.name).font(.headline); Spacer(); Button(W("Remove"), systemImage: "trash", role: .destructive) { remove(record) }.labelStyle(.iconOnly).buttonStyle(.borderless) }
                        Text(record.backgroundRefresh ? W("Direct API refresh enabled") : W("Data from the app")).font(.caption).foregroundStyle(.secondary)
                        Text(record.panel).font(.caption2).foregroundStyle(.secondary)
                        Button(W("Copy data code"), systemImage: "doc.on.doc") {
                            do { var copy = record; copy.backgroundRefresh = false; copy.playerNames = Array((copy.playerNames ?? []).prefix(2000)); Clipboard.copy(try JSONEncoder().encode(copy).base64EncodedString()); report = W("Data code copied. Paste it into Manual snapshot in the widget. This is a fixed copy without credentials or live updates.") } catch { self.error = error.localizedDescription }
                        }.font(.caption)
                    }.padding(.vertical, 4)
                }
            }
            if let api = store.api {
                Section(W("Current panel")) {
                    Button(W("Enable all servers for widgets"), systemImage: "square.grid.2x2") { Task { await addAll() } }.disabled(busy || api.demo)
                    ForEach(store.servers) { server in Button(server.name, systemImage: "plus.circle") { background = true; pending = server }.disabled(busy || api.demo) }
                }
            }
            if WidgetStorage.folder == nil { Section(W("If signing removes App Groups")) { Text(W("The app also tries the shared keychain. If unavailable, iOS cannot connect the app and widget automatically. Sign both with the same App Group, or use the data code as a manual copy. Reinstallation is not required.")).font(.footnote).foregroundStyle(.secondary) } }
        }.panelScreen().navigationTitle(W("Server widgets")).navigationBarTitleDisplayMode(.inline).errorAlert($error).refreshable { records = WidgetStorage.servers() }
            .sheet(item: $pending) { server in
                NavigationStack {
                    Form {
                        Section { Text(server.name).font(.headline); Toggle(W("Refresh directly in widget"), isOn: $background) } footer: { Text(W("Also saves panel access in protected shared widget storage. Widgets can show enabled data while the device is locked.")) }
                        Button(W("Save widget access")) { Task { do { try await add(server, background: background); pending = nil } catch { self.error = error.localizedDescription } } }.disabled(busy)
                    }.panelScreen().navigationTitle(W("Set up widget")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(W("Cancel")) { pending = nil } } }
                }.presentationDetents([.medium, .large])
            }
    }
    func add(_ server: Server, background: Bool) async throws {
        guard let api = store.api else { return }
        var record = WidgetStorage.servers().first(where: { $0.panel == api.base.absoluteString && $0.serverID == server.id }) ?? WidgetServer(panel: api.base.absoluteString, serverID: server.id, name: server.name)
        record.backgroundRefresh = background; record.provider = api.provider.rawValue
        record.memoryLimit = server.data["limits"]["memory"].double > 0 ? server.data["limits"]["memory"].double * 1_048_576 : nil
        if background {
            let original = api.widgetSecret
            var credential = WidgetCredential(provider: api.provider.rawValue, secret: original)
            let encoded = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
            do { try WidgetVault.save(encoded, panel: record.id) }
            catch { record.backgroundRefresh = false; report = W("Signing did not enable shared access. A snapshot was saved locally; use a data code or sign with matching App Groups.") }
        }
        if let data = try? await api.request("servers/\(server.id)/resources").attributes {
            record.state = data["current_state"].string; let r = data["resources"]
            record.cpu = PanelNumbers.number(r["cpu_absolute"]); record.memory = PanelNumbers.number(r["memory_bytes"]); record.disk = PanelNumbers.number(r["disk_bytes"]); record.uptime = PanelNumbers.number(r["uptime"]).map { $0 / 1000 }; record.memoryLimit = PanelNumbers.number(r["memory_limit_bytes"]) ?? record.memoryLimit; record.updated = Date()
        }
        if record.backgroundRefresh { record = await WidgetNetwork.refresh(record) }
        try WidgetStorage.upsert(record); records = WidgetStorage.servers(); WidgetCenter.shared.reloadAllTimelines()
    }
    func addAll() async {
        busy = true; defer { busy = false }
        for server in store.servers { do { try await add(server, background: true) } catch { self.error = error.localizedDescription; break } }
    }
    func refresh() async {
        busy = true; defer { busy = false }
        for record in records where record.backgroundRefresh { let value = await WidgetNetwork.refresh(record); if let issue = value.issue { report = issue } }
        records = WidgetStorage.servers(); WidgetCenter.shared.reloadAllTimelines()
    }
    func remove(_ record: WidgetServer) {
        do { try WidgetStorage.save(WidgetStorage.servers().filter { $0.id != record.id }); records = WidgetStorage.servers(); WidgetVault.delete(record.id); WidgetCenter.shared.reloadAllTimelines() } catch { self.error = error.localizedDescription }
    }
}

