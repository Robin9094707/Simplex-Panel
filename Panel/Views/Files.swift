import SwiftUI
import UniformTypeIdentifiers

struct EditorItem: Identifiable { let id = UUID(); let path: String; var isNew = false }
struct FilesView: View {
    let api: PanelAPI
    let server: Server
    let root: String
    @ObservedObject private var playerNames = PlayerNameCache.shared
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var entries: [JSON] = []
    @State private var matches: [JSON] = []
    @State private var displayCount = 200
    @State private var mover: MoveSelection?
    @State private var nbt: EditorItem?
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var search = ""
    @State private var selected = Set<String>()
    @State private var operation: Operation?
    @State private var editor: EditorItem?
    @State private var importer = false
    @State private var transfer = false
    @State private var showTransfers = false
    @State private var share: ShareItem?
    var prefix: String { "servers/\(server.id)/files" }
    var visible: [JSON] { Array(matches.prefix(displayCount)) }
    var body: some View {
        List(selection: $selected) {
            Section {
                HStack { Label(root, systemImage: "folder").font(.system(.caption, design: .monospaced)).textSelection(.enabled); Spacer(); Text("\(entries.count)").foregroundStyle(.secondary) }
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(W("Search this folder"), text: $search).autocorrectionDisabled().textInputAutocapitalization(.never) }
                HStack { EditButton().buttonStyle(.borderless); Spacer(); Button(workspace.isPinned(api, server, root) ? W("Unpin") : W("Pin"), systemImage: "pin") { workspace.toggleFolder(api, server, root) }.buttonStyle(.borderless); fileTools.buttonStyle(.borderless) }
                if root != "/" { NavigationLink(W("Parent folder")) { FilesView(api: api, server: server, root: parentFolder(root)) } }
                TransferLink()
                if transfer { Text(W("Preparing or transferring files …")).font(.caption).foregroundStyle(.secondary) }
            }
            if loading && !loaded { ProgressView(W("Loading files …")) }
            if loaded && visible.isEmpty { ContentUnavailableView(W("No files"), systemImage: "folder", description: Text(W("Create a file or upload files."))) }
            ForEach(visible, id: \.["name"].string) { entry in
                let name = entry["name"].string
                Group {
                    if entry["is_file"].bool {
                        Button { open(entry) } label: { fileRow(entry) }.buttonStyle(.plain).requiresAccess(api, server.id, "file.read-content")
                    } else {
                        NavigationLink { FilesView(api: api, server: server, root: pathJoin(root, name)) } label: { fileRow(entry) }
                    }
                }.tag(name).onAppear { if visible.last?["name"].string == name && displayCount < matches.count { displayCount += 200 } }.contextMenu { fileActions(entry) }
                    .swipeActions { Button(W("Delete"), role: .destructive) { delete([name]) }.requiresAccess(api, server.id, "file.delete") }
            }
            if !selected.isEmpty {
                Section(W("\(selected.count) selected")) {
                    Button(W("Move selection"), systemImage: "folder") { move(Array(selected)) }.requiresAccess(api, server.id, "file.update")
                    Button(W("Compress selection"), systemImage: "archivebox") { compress(Array(selected)) }.requiresAccess(api, server.id, "file.archive")
                    Button(W("Delete selection"), systemImage: "trash", role: .destructive) { delete(Array(selected)) }.requiresAccess(api, server.id, "file.delete")
                }
            }
        }.panelScreen().navigationTitle(root == "/" ? server.name : URL(fileURLWithPath: root).lastPathComponent)
            .refreshable { await load() }.task { await load(); if root.contains("playerdata") || root.contains("players") { await playerNames.load(api, server) } }
            .task(id: search) { do { try await Task.sleep(for: .milliseconds(180)); await filter() } catch {} }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { selected = []; await load() } }
            .sheet(item: $editor) { FileEditor(api: api, server: server, item: $0) { Task { await load() } } }
            .sheet(item: $mover) { FolderPicker(api: api, server: server, source: root, selection: $0) { selected = []; Task { await load() } } }
            .sheet(item: $nbt) { NBTEditor(api: api, server: server, path: $0.path) }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .sheet(isPresented: $showTransfers) { TransfersView() }
            .sheet(isPresented: $importer) {
                FileImportPicker(multiple: true) { result in
                    importer = false
                    switch result { case .success(let urls): if !urls.isEmpty { upload(urls) }; case .failure(let e): error = e.localizedDescription }
                }.ignoresSafeArea()
            }.errorAlert($error)
    }
    var fileTools: some View {
        Menu {
            Button(W("Upload"), systemImage: "square.and.arrow.up") { importer = true }.requiresRequest(api, prefix + "/upload", method: "GET")
            Button(W("New file"), systemImage: "doc.badge.plus") { createFile() }.requiresAccess(api, server.id, "file.update")
            Button(W("New folder"), systemImage: "folder.badge.plus") { operation = Operation(title: W("Create folder"), path: prefix + "/create-folder", fields: [Field(key: "name", label: W("Folder name"))], fixed: ["root": .string(root)]) }.requiresRequest(api, prefix + "/create-folder", method: "POST")
            Button(W("Download from URL"), systemImage: "link") { operation = Operation(title: W("Download file from URL"), detail: W("The server downloads the file directly from this URL. The standard Client API only confirms the request and does not report percentage progress. Check the target folder afterwards. For measurable progress, download to your iPhone first, then upload."), path: prefix + "/pull", fields: [Field(key: "url", label: "https://…")], fixed: ["directory": .string(root)]) }.requiresRequest(api, prefix + "/pull", method: "POST")
            Button(W("Refresh"), systemImage: "arrow.clockwise") { Task { await load() } }
        } label: { Label(W("Actions"), systemImage: "plus.circle") }.disabled(transfer)
    }
    func fileRow(_ entry: JSON) -> some View {
        HStack(spacing: 14) {
            Image(systemName: entry["is_file"].bool ? "doc.text" : "folder.fill").font(.title3).foregroundStyle(entry["is_file"].bool ? Color.secondary : Color.teal).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(playerNames.name(api, server, filename: entry["name"].string) ?? entry["name"].string).font(.body).lineLimit(2)
                if playerNames.name(api, server, filename: entry["name"].string) != nil { Text(entry["name"].string).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                HStack { Text(entry["is_file"].bool ? bytes(entry["size"].double) : W("Folder")); if !entry["modified_at"].string.isEmpty { Text(entry["modified_at"].string.prefix(16).replacingOccurrences(of: "T", with: " ")) } }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
    @ViewBuilder func fileActions(_ entry: JSON) -> some View {
        let name = entry["name"].string
        if entry["is_file"].bool {
            Button(W("Edit"), systemImage: "pencil") { open(entry) }.requiresAccess(api, server.id, "file.read-content")
            Button(W("Download"), systemImage: "square.and.arrow.down") { download(entry) }.requiresAccess(api, server.id, "file.read-content")
            if true {
            Button(W("Copy"), systemImage: "doc.on.doc") { operation = Operation(title: W("Copy file"), path: prefix + "/copy", fixed: ["location": .string(pathJoin(root, name))], submit: W("Copy")) }.requiresRequest(api, prefix + "/copy", method: "POST")
            }
            Button(W("Extract"), systemImage: "archivebox") { operation = Operation(title: W("Extract archive"), path: prefix + "/decompress", fixed: ["root": .string(root), "file": .string(name)], submit: W("Extract")) }.requiresRequest(api, prefix + "/decompress", method: "POST")
        }
        if !entry["is_file"].bool { Button(W("Pin folder"), systemImage: "pin") { workspace.toggleFolder(api, server, pathJoin(root, name)) } }
        Button(W("Move …"), systemImage: "folder") { move([name]) }.requiresAccess(api, server.id, "file.update")
        Button(W("Rename"), systemImage: "pencil.line") { rename(name) }.requiresAccess(api, server.id, "file.update")
        Button(W("Compress"), systemImage: "archivebox.fill") { compress([name]) }.requiresAccess(api, server.id, "file.archive")
        if true { Button(W("File permissions"), systemImage: "lock.doc") { chmod(name) }.requiresAccess(api, server.id, "file.update") }
        Button(W("Delete"), systemImage: "trash", role: .destructive) { delete([name]) }.requiresAccess(api, server.id, "file.delete")
    }
    func filter() async {
        let values = entries, term = search
        let result = await Task.detached(priority: .userInitiated) { values.filter { term.isEmpty || $0["name"].string.localizedCaseInsensitiveContains(term) } }.value
        guard term == search, !Task.isCancelled else { return }; matches = result; displayCount = 200
    }
    func load() async { loading = true; defer { loading = false }; do {
        let values = try await api.list(prefix + "/list", query: ["directory": root])
        entries = await Task.detached(priority: .userInitiated) { values.sorted { a, b in if a["is_file"].bool != b["is_file"].bool { return !a["is_file"].bool }; return a["name"].string.localizedStandardCompare(b["name"].string) == .orderedAscending } }.value
        await filter(); loaded = true
    } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    func move(_ names: [String]) { mover = MoveSelection(names: names, directories: Set(entries.filter { !$0["is_file"].bool }.map { $0["name"].string }).intersection(names)) }
    func open(_ entry: JSON) {
        if entry["size"].double > 8 * 1024 * 1024 { error = W("The editor opens files up to 8 MiB. Larger files can be downloaded."); return }
        let path = pathJoin(root, entry["name"].string)
        if ["dat", "nbt", "schem", "schematic"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) { nbt = EditorItem(path: path) }
        else { editor = EditorItem(path: path) }
    }
    func createFile() { editor = EditorItem(path: root, isNew: true) }
    func delete(_ names: [String]) { operation = Operation(title: W("Delete files"), detail: W("\(names.joined(separator: ", "))\n\nFiles and contained folders will be permanently deleted."), path: prefix + "/delete", fixed: ["root": .string(root), "files": .array(names.map(JSON.string))], destructive: true, submit: W("Delete permanently")) }
    func compress(_ names: [String]) { operation = Operation(title: W("Create archive"), path: prefix + "/compress", fixed: ["root": .string(root), "files": .array(names.map(JSON.string))], submit: W("Compress")) }
    func rename(_ name: String) {
        operation = Operation(title: W("Rename"), path: prefix + "/rename", method: "PUT", fields: [Field(key: "to", label: W("New name"), value: name)], transform: { values in
            let target = values["to"]?.string ?? ""
            guard !target.contains("/"), ![".", ".."].contains(target), !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PanelError(message: W("Enter a name.")) }
            return .object(["root": .string(root), "files": .array([.object(["from": .string(name), "to": .string(target)])])])
        })
    }
    func chmod(_ name: String) {
        operation = Operation(title: W("Change file permissions"), path: prefix + "/chmod", fields: [Field(key: "mode", label: W("Unix permissions"), value: "0644", hint: W("For example, 0644 for files or 0755 for folders."))], destructive: true, transform: { values in
            let mode = values["mode"]?.string ?? ""
            guard mode.range(of: "^[0-7]{3,4}$", options: .regularExpression) != nil else { throw PanelError(message: W("Enter three or four octal digits.")) }
            return .object(["root": .string(root), "files": .array([.object(["file": .string(name), "mode": .string(mode)])])])
        })
    }
    func upload(_ urls: [URL]) {
        transfer = true
        Task { defer { transfer = false }; do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask { @MainActor in
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw PanelError(message: W("Select files. Folders cannot be uploaded directly.")) }
                        try await api.upload(server: server.id, directory: root, file: url)
                    }
                }
                try await group.waitForAll()
            }; await load()
        } catch { self.error = error.localizedDescription } }
    }
    func download(_ entry: JSON) {
        transfer = true
        Task { defer { transfer = false }; do {
            guard !api.demo else { throw PanelError(message: W("Downloads are disabled in demo mode.")) }
            let result = try await api.request(prefix + "/download", query: ["file": pathJoin(root, entry["name"].string)])
            try TransferManager.shared.download(BackupInfo.downloadURL(result, base: api.base), filename: entry["name"].string, context: server.name + " · " + root, source: DownloadSource(panel: api.base.absoluteString, server: server.id, kind: "file", resource: pathJoin(root, entry["name"].string)))
            showTransfers = true
        } catch { self.error = error.localizedDescription } }
    }
}
struct FileEditor: View {
    let api: PanelAPI
    let server: Server
    let item: EditorItem
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var access: ServerAccess
    init(api: PanelAPI, server: Server, item: EditorItem, onSave: @escaping () -> Void) {
        self.api = api; self.server = server; self.item = item; self.onSave = onSave; self.access = api.access
    }
    @State private var text = ""
    @State private var original = ""
    @State private var name = ""
    @State private var loading = true
    @State private var failed = false
    @State private var saving = false
    @State private var error: String?
    @State private var discard = false
    @State private var yamlForm = false
    @AppStorage("syntaxColors") private var syntaxColors = true
    var dirty: Bool { text != original || item.isNew }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if item.isNew { TextField(W("Filename, e.g. config.yml"), text: $name).textFieldStyle(.roundedBorder).padding().textInputAutocapitalization(.never).autocorrectionDisabled() }
                if loading { Spacer(); ProgressView(W("Loading content …")); Spacer() }
                else if failed { ContentUnavailableView(W("Cannot open file"), systemImage: "doc.questionmark", description: Text(W("Download it or try again."))) }
                else { SyntaxEditor(text: $text, colors: syntaxColors, editable: access.allows(server.id, "file.update")).frame(maxWidth: .infinity, maxHeight: .infinity) }
                HStack { Text(access.allows(server.id, "file.update") ? "UTF-8" : W("Read only · permission denied")); Spacer(); Text(bytes(Double(text.utf8.count))) }.font(.caption.monospaced()).foregroundStyle(.secondary).padding(12).background(.bar)
            }.panelScreen().navigationTitle(item.isNew ? W("New file") : URL(fileURLWithPath: item.path).lastPathComponent).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(W("Close")) { if dirty { discard = true } else { dismiss() } }.disabled(saving) }
                    ToolbarItem(placement: .primaryAction) { Menu {
                        Toggle(W("Syntax colors"), isOn: $syntaxColors)
                        if ["yml", "yaml", "properties"].contains(URL(fileURLWithPath: item.isNew ? name : item.path).pathExtension.lowercased()) { Button(W("Edit values as a form"), systemImage: "slider.horizontal.3") { yamlForm = true }.disabled(loading || failed || !access.allows(server.id, "file.update")) }
                    } label: { Image(systemName: "textformat") }.accessibilityLabel(W("Editor options")) }
                    ToolbarItem(placement: .confirmationAction) { Button { save() } label: { if saving { ProgressView() } else { Text(W("Save")).bold() } }.disabled(loading || failed || saving || (item.isNew && name.isEmpty) || !dirty).requiresAccess(api, server.id, "file.update") }
                }.interactiveDismissDisabled(dirty || saving).errorAlert($error)
                .sheet(isPresented: $yamlForm) { ConfigurationForm(text: $text, properties: URL(fileURLWithPath: item.isNew ? name : item.path).pathExtension.lowercased() == "properties") }
                .confirmationDialog(W("Discard changes?"), isPresented: $discard, titleVisibility: .visible) { Button(W("Discard"), role: .destructive) { dismiss() } }
                .task {
                    if item.isNew { loading = false; return }
                    do { text = try await api.fileText(server: server.id, path: item.path); original = text } catch { failed = true; self.error = error.localizedDescription }; loading = false
                }
        }
    }
    func save() {
        saving = true
        Task { do {
            guard !api.demo else { throw PanelError(message: W("Demo mode does not save files.")) }
            if item.isNew {
                guard !name.contains("/"), ![".", ".."].contains(name), !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PanelError(message: W("Enter a valid filename without slashes.")) }
                let existing = try await api.list("servers/\(server.id)/files/list", query: ["directory": item.path])
                guard !existing.contains(where: { $0["name"].string == name }) else { throw PanelError(message: W("A file with this name already exists. Open it using Edit.")) }
            }
            if !item.isNew {
                let current = try await api.fileText(server: server.id, path: item.path)
                guard current == original else { throw PanelError(message: W("This file has changed on the server. Copy your edits and reopen the file to compare both versions.")) }
            }
            _ = try await api.raw("servers/\(server.id)/files/write", method: "POST", query: ["file": item.isNew ? pathJoin(item.path, name) : item.path], text: text)
            original = text; onSave(); dismiss()
        } catch { self.error = error.localizedDescription }; saving = false }
    }
}

