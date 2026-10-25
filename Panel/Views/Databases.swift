import SwiftUI

struct DatabasesView: View {
    let api: PanelAPI
    let server: Server
    @State private var rows: [JSON] = []
    @State private var error: String?
    @State private var operation: Operation?
    @State private var selected: DetailItem?
    @State private var loading = false
    var prefix: String { "servers/\(server.id)/databases" }
    var body: some View {
        List {
            Section {
                Text(W("Connection details, passwords and database management. Tables and SQL content are not accessible through this panel API.")).font(.footnote).foregroundStyle(.secondary)
                Button(W("Create database"), systemImage: "plus") { operation = Operation(title: W("Create database"), path: prefix, fields: [Field(key: "database", label: W("Name")), Field(key: "remote", label: W("Allowed source address"), value: "%")], submit: W("Create")) }.requiresRequest(api, prefix, method: "POST")
            }
            if loading { ProgressView() }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let db = DatabaseInfo(value: row)
                Button { selected = DetailItem(data: row) } label: {
                    HStack(spacing: 14) { Image(systemName: "externaldrive.fill").font(.title2).foregroundStyle(Color.panelAccent); VStack(alignment: .leading, spacing: 6) { Text(db.name).font(.headline); Text("\(db.host):\(db.port)").font(.caption.monospaced()).foregroundStyle(.secondary); Text(row["username"].string).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }
                }.buttonStyle(.plain)
            }
            if !loading && rows.isEmpty { ContentUnavailableView(W("No databases"), systemImage: "externaldrive") }
        }.panelScreen().navigationTitle(W("Databases")).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }.errorAlert($error)
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
            .sheet(item: $selected) { item in DatabaseDetail(api: api, server: server, initial: item.data) { await load() } }
    }
    func load() async { loading = true; defer { loading = false }; do { rows = try await api.list(prefix) } catch { self.error = error.localizedDescription } }
}
struct DatabaseDetail: View {
    let api: PanelAPI
    let server: Server
    let initial: JSON
    let changed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: JSON = .null
    @State private var reveal = false
    @State private var error: String?
    @State private var operation: Operation?
    var row: JSON { value == .null ? initial : value }
    var db: DatabaseInfo { DatabaseInfo(value: row) }
    var body: some View {
        NavigationStack {
            Form {
                Section(W("Connection")) {
                    copyRow(W("Database"), db.name); copyRow("Host", db.host); copyRow("Port", db.port); copyRow(W("User"), row["username"].string)
                    copyRow(W("Allowed source address"), row["connections_from"].string)
                }
                Section(W("Password")) {
                    if !db.password.isEmpty { HStack { Text(reveal ? db.password : "••••••••••••").font(.system(.body, design: .monospaced)).textSelection(.enabled); Spacer(); Button(reveal ? W("Hide") : W("Show"), systemImage: reveal ? "eye.slash" : "eye") { reveal.toggle() }.labelStyle(.iconOnly); Button(W("Copy"), systemImage: "doc.on.doc") { Clipboard.copy(db.password) }.labelStyle(.iconOnly) } }
                    else { Button(W("Load password"), systemImage: "key") { Task { await password() } }.requiresAccess(api, server.id, "database.view_password") }
                    Button(W("Rotate password"), systemImage: "arrow.clockwise", role: .destructive) { operation = Operation(title: W("Rotate password"), detail: W("Plugin configurations must use the new password afterwards."), path: "servers/\(server.id)/databases/\(row["id"].string)/rotate-password", destructive: true, submit: W("Rotate")) }.requiresRequest(api, "servers/\(server.id)/databases/\(row["id"].string)/rotate-password", method: "POST")
                }
                Section {
                    Button(W("Copy connection details"), systemImage: "doc.on.doc") { Clipboard.copy("Host: \(db.host)\nPort: \(db.port)\nDatabase: \(db.name)\nUser: \(row["username"].string)") }
                    Button(W("Delete database"), systemImage: "trash", role: .destructive) { operation = Operation(title: W("Delete database"), detail: W("All tables and data in this database will be permanently deleted."), path: "servers/\(server.id)/databases/\(row["id"].string)", method: "DELETE", destructive: true, submit: W("Delete permanently")) }.requiresRequest(api, "servers/\(server.id)/databases/\(row["id"].string)", method: "DELETE")
                }
            }.panelScreen().refreshable { await reload() }.navigationTitle(db.name).navigationBarTitleDisplayMode(.inline).privacySensitive().errorAlert($error)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { dismiss() } } }
                .sheet(item: $operation) { op in OperationSheet(api: api, operation: op) { await changed(); if op.method == "DELETE" { dismiss() } else { value = .null; reveal = false; await password() } } }
        }
    }
    func copyRow(_ title: String, _ text: String) -> some View { HStack { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(text.isEmpty ? "–" : text).textSelection(.enabled) }; Spacer(); if !text.isEmpty { Button(W("Copy"), systemImage: "doc.on.doc") { Clipboard.copy(text) }.labelStyle(.iconOnly).buttonStyle(.borderless) } } }
    func reload() async { do {
        let rows = try await api.list("servers/\(server.id)/databases", query: reveal ? ["include": "password"] : [:])
        guard let found = rows.first(where: { $0["id"] == initial["id"] }) else { throw PanelError(message: W("Database no longer exists.")) }
        value = found
    } catch { self.error = error.localizedDescription } }
    func password() async { do { let rows = try await api.list("servers/\(server.id)/databases", query: ["include": "password"]); guard let found = rows.first(where: { $0["id"] == initial["id"] }) else { throw PanelError(message: W("Database no longer exists.")) }; value = found; if db.password.isEmpty { error = W("The provider did not return a password or your account does not have permission to view it.") } } catch { self.error = error.localizedDescription } }
}

