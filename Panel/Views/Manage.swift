import SwiftUI

struct ManageView: View {
    let api: PanelAPI
    let server: Server
    @State private var operation: Operation?
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: WorkspaceStore
    var live: LiveServer? = nil
    var prefix: String { "servers/\(server.id)" }
    var body: some View {
        List {
            if workspace.isMinecraft(api, server) {
            Section("Minecraft") {
                if let live { NavigationLink { PlayerManagerView(api: api, server: server, live: live) } label: { Label(W("Player manager"), systemImage: "person.crop.circle.badge.checkmark") } }
                NavigationLink { ModsView(api: api, server: server) } label: { Label(W("Mods & mod updates"), systemImage: "shippingbox") }.requiresAccess(api, server.id, "file.read")
                NavigationLink { PluginsView(api: api, server: server) } label: { Label(W("Plugins & JAR files"), systemImage: "puzzlepiece.extension") }.requiresAccess(api, server.id, "file.read")
                NavigationLink { MinecraftPropertiesView(api: api, server: server) } label: { Label(W("Minecraft & world settings"), systemImage: "globe") }.requiresAccess(api, server.id, "file.read-content")
            }
            }
            Section(W("Manage server")) {
                NavigationLink { SchedulesView(api: api, server: server) } label: { Label(W("Schedules"), systemImage: "calendar.badge.clock") }.requiresAccess(api, server.id, "schedule.read")
                NavigationLink { DatabasesView(api: api, server: server) } label: { Label(W("Databases"), systemImage: "externaldrive.connected.to.line.below") }.requiresAccess(api, server.id, "database.read")
                NavigationLink { ResourcesView(api: api, server: server, kind: .network) } label: { Label(W("Network & ports"), systemImage: "network") }.requiresAccess(api, server.id, "allocation.read")
                NavigationLink { ResourcesView(api: api, server: server, kind: .users) } label: { Label(W("Subusers"), systemImage: "person.2") }.requiresAccess(api, server.id, "user.read")
                NavigationLink { StartupView(api: api, server: server) } label: { Label(W("Startup parameters"), systemImage: "play.rectangle") }.requiresAccess(api, server.id, "startup.read")
                NavigationLink { ActivityView(api: api, path: prefix + "/activity") } label: { Label(W("Activity"), systemImage: "clock.arrow.circlepath") }.requiresAccess(api, server.id, "activity.read")
            }
            Section(W("Settings")) {
                Button(W("Name & description"), systemImage: "pencil") { operation = Operation(title: W("Rename server"), path: prefix + "/settings/rename", fields: [Field(key: "name", label: W("Name"), value: server.name), Field(key: "description", label: W("Description"), value: server.data["description"].string, kind: .multiline)]) }.requiresRequest(api, prefix + "/settings/rename", method: "POST")
                Button(W("Change Docker image"), systemImage: "shippingbox") { operation = Operation(title: W("Change Docker image"), detail: W("Use an image approved by your provider for this server. Changes apply on the next start."), path: prefix + "/settings/docker-image", method: "PUT", fields: [Field(key: "docker_image", label: "Docker-Image", value: server.data["docker_image"].string)], destructive: true) }.requiresRequest(api, prefix + "/settings/docker-image", method: "PUT")
                Button(W("Reinstall server"), systemImage: "arrow.triangle.2.circlepath", role: .destructive) { operation = Operation(title: W("Reinstall server"), detail: W("The installation script will run again and may change or overwrite server files. Create a backup first."), path: prefix + "/settings/reinstall", destructive: true, submit: W("Reinstall")) }.requiresRequest(api, prefix + "/settings/reinstall", method: "POST")
            }
            Section("SFTP") {
                LabeledContent("Host", value: server.data["sftp_details"]["ip"].string).textSelection(.enabled)
                LabeledContent("Port", value: server.data["sftp_details"]["port"].string)
                Text(W("SFTP credentials depend on your panel account. The Client API key is not an SFTP password.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink { JSONDetails(title: W("Server details"), data: server.data) } label: { Label(W("All server information"), systemImage: "info.circle") }
            } footer: { Text(W("Panel actions use the Client API. Your provider determines permissions, resource limits and available features.")) }
        }.panelScreen().refreshable { await api.loadAccess(server: server.id); await store.refresh(); if let live { try? await live.refresh(api: api, server: server, minecraft: true) } }.sheet(item: $operation) { OperationSheet(api: api, operation: $0) }
    }
}

enum ResourceKind {
    case databases, network, users
    var title: String { switch self { case .databases: return W("Databases"); case .network: return W("Network & ports"); case .users: return W("Subusers") } }
    var path: String { switch self { case .databases: return "databases"; case .network: return "network/allocations"; case .users: return "users" } }
    var symbol: String { switch self { case .databases: return "externaldrive"; case .network: return "network"; case .users: return "person.2" } }
}
struct ResourcesView: View {
    let api: PanelAPI
    let server: Server
    let kind: ResourceKind
    @State private var rows: [JSON] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var operation: Operation?
    @State private var detail: DetailItem?
    @State private var userEditor: DetailItem?
    var prefix: String { "servers/\(server.id)/" + kind.path }
    var body: some View {
        List {
            if !loaded { ProgressView(W("Loading …")) }
            if loaded && rows.isEmpty { ContentUnavailableView(W("No entries"), systemImage: kind.symbol) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title(row)).font(.headline)
                            Text(subtitle(row)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }; Spacer()
                        Menu { actions(row) } label: { Image(systemName: "ellipsis.circle").font(.title3).padding(6) }
                    }.padding(.vertical, 6)
                    if kind == .users {
                        Text(W("\(row["permissions"].array.count) permissions")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.panelScreen().navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline).refreshable { await load() }.task { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(W("Add"), systemImage: "plus") { create() }.requiresRequest(api, prefix) } }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
            .sheet(item: $userEditor) { item in SubuserEditor(api: api, server: server, initial: item.data) { await load() } }
            .sheet(item: $detail) { item in NavigationStack { JSONDetails(title: "Details", data: item.data).toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { detail = nil } } } } }
            .errorAlert($error)
    }
    func title(_ row: JSON) -> String { switch kind { case .databases: return row["name"].string; case .network: return "\(row["ip_alias"].string.isEmpty ? row["ip"].string : row["ip_alias"].string):\(row["port"].string)"; case .users: return row["email"].string } }
    func subtitle(_ row: JSON) -> String { switch kind { case .databases: return "\(row["username"].string) · \(row["host"]["address"].string):\(row["host"]["port"].string)"; case .network: return (row["is_default"].bool ? W("Primary · ") : "") + row["notes"].string; case .users: return row["username"].string } }
    @ViewBuilder func actions(_ row: JSON) -> some View {
        let id = kind == .users ? row["uuid"].string : row["id"].string
        Button("Details", systemImage: "info.circle") { detail = DetailItem(data: row) }
        switch kind {
        case .databases:
            Button(W("View password"), systemImage: "key") { Task { do { let result = try await api.list(prefix, query: ["include": "password"]); detail = DetailItem(data: result.first(where: { $0["id"].string == id }) ?? .null) } catch { self.error = error.localizedDescription } } }.requiresAccess(api, server.id, "database.view_password")
            Button(W("Rotate password"), systemImage: "arrow.clockwise", role: .destructive) { operation = Operation(title: W("Rotate database password"), detail: W("Plugins and applications must use the new password afterwards."), path: prefix + "/\(id)/rotate-password", destructive: true, submit: W("Rotate")) }.requiresRequest(api, prefix + "/\(id)/rotate-password", method: "POST")
        case .network:
            Button(W("Edit note"), systemImage: "pencil") { operation = Operation(title: W("Port note"), path: prefix + "/\(id)", method: "POST", fields: [Field(key: "notes", label: W("Note"), value: row["notes"].string)]) }.requiresRequest(api, prefix + "/\(id)", method: "POST")
            if !row["is_default"].bool { Button(W("Set as primary"), systemImage: "star") { operation = Operation(title: W("Change primary port"), path: prefix + "/\(id)" + "/primary", method: "POST", fixed: [:], submit: W("Set")) }.requiresRequest(api, prefix + "/\(id)" + "/primary", method: "POST") }
        case .users:
            Button(W("Edit permissions"), systemImage: "person.badge.key") { userEditor = DetailItem(data: row) }.requiresRequest(api, prefix + "/\(id)", method: "POST")
        }
        Button(W("Remove"), systemImage: "trash", role: .destructive) { operation = Operation(title: W("Remove entry"), detail: kind == .databases ? W("The database and all its data will be permanently deleted.") : "\(title(row)) wird entfernt.", path: prefix + "/\(id)", method: "DELETE", destructive: true, submit: W("Remove")) }.disabled(kind == .network && row["is_default"].bool).requiresRequest(api, prefix + "/\(id)", method: "DELETE")
    }
    func create() {
        switch kind {
        case .databases:
            operation = Operation(title: W("Create database"), path: prefix, fields: [Field(key: "database", label: W("Database name")), Field(key: "remote", label: W("Allowed connections"), value: "%", hint: W("% allows all source addresses. Use a fixed address when possible."))], submit: W("Create"))
        case .network:
            operation = Operation(title: W("Assign port"), detail: W("Your provider must support automatic assignment of additional ports."), path: prefix, submit: W("Request port"))
        case .users:
            userEditor = DetailItem(data: .null)
        }
    }
    func load() async { do { rows = try await api.list(prefix); loaded = true } catch is CancellationError {} catch { self.error = error.localizedDescription } }
}
struct DetailItem: Identifiable { let id = UUID(); let data: JSON }

struct StartupView: View {
    let api: PanelAPI
    let server: Server
    @State private var variables: [JSON] = []
    @State private var operation: Operation?
    @State private var error: String?
    var body: some View {
        List {
            Section(W("Startup command")) { Text(server.data["invocation"].string).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
            ForEach(variables, id: \.["env_variable"].string) { v in
                Section {
                    VStack(alignment: .leading, spacing: 8) { Text(v["name"].string).font(.headline); Text(v["server_value"].string).font(.system(.body, design: .monospaced)).textSelection(.enabled); Text(v["description"].string).font(.caption).foregroundStyle(.secondary) }
                    if v["is_editable"].bool {
                        Button(W("Change value"), systemImage: "pencil") { operation = Operation(title: v["name"].string, detail: v["rules"].string, path: "servers/\(server.id)/startup/variable", method: "PUT", fields: [Field(key: "value", label: W("Value"), value: v["server_value"].string)], fixed: ["key": v["env_variable"]]) }.requiresRequest(api, "servers/\(server.id)/startup/variable", method: "PUT")
                    } else { Label(W("Managed by provider"), systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.panelScreen().navigationTitle(W("Startup parameters")).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }.errorAlert($error)
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
    }
    func load() async { do { variables = try await api.list("servers/\(server.id)/startup") } catch { self.error = error.localizedDescription } }
}
struct ActivityView: View {
    let api: PanelAPI
    let path: String
    @State private var events: [JSON] = []
    @State private var error: String?
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    var body: some View {
        List {
            if events.isEmpty && !loading { ContentUnavailableView(W("No activity"), systemImage: "clock.arrow.circlepath") }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                NavigationLink { JSONDetails(title: W("Activity"), data: event) } label: { VStack(alignment: .leading, spacing: 6) { Text(event["event"].string).font(.subheadline.weight(.medium)); Text(event["timestamp"].string).font(.caption).foregroundStyle(.secondary) } }
            }
            if loading { ProgressView(W("Loading activity …")) }
            else if more { Button(W("Load more activity")) { Task { await load(reset: false) } } }
        }.panelScreen().navigationTitle(W("Activity")).navigationBarTitleDisplayMode(.inline).task { await load(reset: true) }.refreshable { await load(reset: true) }.errorAlert($error)
    }
    func load(reset: Bool) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let requested = reset ? 1 : page
            let result = try await api.request(path, query: ["page": String(requested), "per_page": "50"])
            if reset { events = result.rows } else { events += result.rows }
            let pages = result["meta"]["pagination"]["total_pages"].int
            more = requested < pages; page = requested + 1
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

