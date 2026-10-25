import SwiftUI

struct SubuserEditor: View {
    let api: PanelAPI
    let server: Server
    let initial: JSON
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog: PermissionCatalogStore
    @ObservedObject private var access: ServerAccess
    @State private var email: String
    @State private var selected: Set<String>
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?
    init(api: PanelAPI, server: Server, initial: JSON = .null, done: @escaping () async -> Void) {
        self.api = api; self.server = server; self.initial = initial; self.done = done; catalog = api.permissions; access = api.access
        _email = State(initialValue: initial["email"].string); _selected = State(initialValue: Set(initial["permissions"].array.map(\.string)))
    }
    var known: Set<String> { Set(catalog.groups.flatMap { $0.choices.map(\.id) }) }
    var missing: [String] { selected.subtracting(known).sorted() }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if initial == .null { TextField(W("Email address"), text: $email).keyboardType(.emailAddress).autocorrectionDisabled().textInputAutocapitalization(.never) }
                    else { LabeledContent(W("Subusers"), value: email) }
                    Label(W("\(selected.count) permissions selected"), systemImage: "person.badge.key")
                    Text(W("The permission catalog and descriptions come directly from your panel. You can only grant permissions you hold; the panel performs the final check.")).font(.caption).foregroundStyle(.secondary)
                }
                if catalog.loading { ProgressView(W("Loading available permissions …")) }
                if let issue = catalog.issue {
                    Section {
                        Text(issue).foregroundStyle(.orange)
                        Button(W("Reload permission catalog")) { Task { await catalog.load(api) } }
                    }
                }
                ForEach(catalog.groups) { group in
                    let choices = group.choices.filter { search.isEmpty || ($0.id + " " + $0.title + " " + $0.description + " " + group.title).localizedCaseInsensitiveContains(search) }
                    if !choices.isEmpty {
                        Section {
                            ForEach(choices) { permission in
                                Toggle(isOn: Binding(get: { selected.contains(permission.id) }, set: { value in if value { selected.insert(permission.id) } else { selected.remove(permission.id) } })) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(permission.title).font(.subheadline.weight(.semibold))
                                        Text(permission.id).font(.system(.caption, design: .monospaced)).foregroundStyle(Color.panelAccent)
                                        if !permission.description.isEmpty { Text(permission.description).font(.caption).foregroundStyle(.secondary) }
                                        if !access.allows(server.id, permission.id) { Label(W("Not available to grant"), systemImage: "lock").font(.caption2).foregroundStyle(.orange) }
                                    }.padding(.vertical, 3)
                                }.disabled(!access.allows(server.id, permission.id) && !selected.contains(permission.id)).accessibilityIdentifier("permission-" + permission.id)
                            }
                        } header: { Text(group.title) } footer: { if !group.description.isEmpty { Text(group.description) } }
                    }
                }
                if !missing.isEmpty {
                    Section { ForEach(missing, id: \.self) { id in Toggle(id, isOn: Binding(get: { selected.contains(id) }, set: { if !$0 { selected.remove(id) } })).font(.system(.caption, design: .monospaced)) } } header: { Text(W("Other existing permissions")) } footer: { Text(W("These previously granted permissions are missing from the loaded catalog. They are preserved unless you deselect them.")) }
                }
            }.panelScreen().navigationTitle(initial == .null ? W("Add subuser") : W("Permissions")).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: W("Search permissions"))
                .refreshable { await api.loadAccess(server: server.id); await catalog.load(api) }
                .task { await api.loadAccess(server: server.id); await catalog.load(api) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(W("Cancel")) { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button(W("Save")) { save() }.disabled(busy || selected.isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (initial == .null && catalog.groups.isEmpty)) }
                }.errorAlert($error).interactiveDismissDisabled(busy)
        }
    }
    func save() { busy = true; Task { defer { busy = false }; do {
        var body: [String: JSON] = ["permissions": .array(selected.sorted().map(JSON.string))]
        if initial == .null { body["email"] = .string(email.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let id = initial["uuid"].string.isEmpty ? initial["id"].string : initial["uuid"].string
        guard initial == .null || (!id.isEmpty && !id.contains("/")) else { throw PanelError(message: W("The user does not have a valid API ID.")) }
        _ = try await api.request("servers/\(server.id)/users" + (initial == .null ? "" : "/" + id), method: "POST", body: .object(body))
        await done(); dismiss()
    } catch { self.error = error.localizedDescription } } }
}

