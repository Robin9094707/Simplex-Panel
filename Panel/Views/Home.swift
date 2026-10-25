import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var add = false
    @State private var settings = false
    @State private var transfers = false
    @State private var widgets = false
    @State private var search = ""
    @State private var editLayout = false
    @State private var iconRevision = 0
    @ObservedObject private var layouts = DashboardLayouts.shared
    var layoutKey: String { "home:" + (store.api?.base.absoluteString ?? "none") + "|" + (store.demo ? "demo" : store.selected?.uuidString ?? "none") }
    var filtered: [Server] { store.servers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.node.localizedCaseInsensitiveContains(search) }.sorted { a, b in
        guard let api = store.api else { return a.name < b.name }
        let ap = workspace.favorites.contains(workspace.key(api, a)), bp = workspace.favorites.contains(workspace.key(api, b))
        return ap == bp ? a.name.localizedStandardCompare(b.name) == .orderedAscending : ap
    } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let api = store.api {
                        ForEach(layouts.cards(layoutKey, scope: .home)) { card in homeCard(card, api: api) }
                        if store.demo { Button(W("Connect your own panel"), systemImage: "plus") { add = true }.buttonStyle(.glassProminent).frame(maxWidth: .infinity) }
                    } else { hero; welcome }
                }.padding(.bottom, 60).padding(22).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.panelScreen().navigationTitle("Simplex Wing").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: W("Search servers"))
                .refreshable { iconRevision += 1; await store.refresh(); await store.refreshPresence() }.scrollBounceBehavior(.always)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(store.profiles) { p in Button { store.select(p.id) } label: { Label(p.name, systemImage: store.selected == p.id && !store.demo ? "checkmark.circle.fill" : "server.rack") } }
                            Button(W("Add panel"), systemImage: "plus") { add = true }
                            if store.demo { Button(W("Exit demo")) { store.exitDemo() } }
                        } label: { Label(store.demo ? "Demo" : store.active?.name ?? "Panels", systemImage: "square.stack") }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button(W("Customize home"), systemImage: "rectangle.3.group") { editLayout = true }.disabled(store.api == nil).accessibilityIdentifier("editHomeLayout") }
                    ToolbarItem(placement: .topBarTrailing) { Button(W("Transfers"), systemImage: "arrow.up.arrow.down.circle") { transfers = true } }
                    ToolbarItem(placement: .topBarTrailing) { Button(W("Settings"), systemImage: "slider.horizontal.3") { settings = true } }
                }
                .navigationDestination(for: Server.self) { server in if let api = store.api { ServerView(api: api, server: server).id("\(store.selected?.uuidString ?? "demo")-\(server.id)") } }
                .sheet(isPresented: $editLayout) { DashboardEditor(scope: .home, layoutKey: layoutKey) }
                .sheet(isPresented: $add) { AddPanelView() }
                .sheet(isPresented: $settings) { SettingsView() }
                .sheet(isPresented: $transfers) { TransfersView() }
                .sheet(isPresented: $widgets) { NavigationStack { WidgetSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { widgets = false } } } } }
                .onOpenURL { url in if url.host == "transfers" { transfers = true }; if url.host == "widgets" { widgets = true } }
                .task(id: store.api.map { ObjectIdentifier($0) }) { await store.refresh(); await store.pollPresence() }
        }
    }
    func isBedrockOnly(_ server: Server) -> Bool {
        let container = server.data["container"]["image"].string.lowercased()
        let invocation = server.data["invocation"].string.lowercased()
        return container.contains("bedrock") || invocation.contains("bedrock_server")
    }
    var hero: some View {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.demo ? "DEMO WORKSPACE" : W("YOUR WORKSPACE")).font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.panelAccent)
                            Text(W("Everything\nunder control.")).font(.system(size: 39, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                            Text(store.demo ? W("Sample data · no connection to real servers") : store.active?.url ?? W("Connect your Pterodactyl panel.")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "server.rack").font(.system(size: 32, weight: .light)).foregroundStyle(Color.panelAccent).padding(20).glassEffect(.regular.tint(.teal.opacity(0.12)), in: .rect(cornerRadius: 25))
                    }.padding(.top, 16)
    }
    var serverList: some View {
        VStack(alignment: .leading, spacing: 18) {
                        HStack { Label(W("\(store.servers.count) servers"), systemImage: "square.stack.3d.up").font(.subheadline.weight(.medium)); Spacer(); if store.loading { ProgressView() } }
                        if filtered.isEmpty {
                            ContentUnavailableView(search.isEmpty ? W("No servers") : W("No results"), systemImage: "server.rack", description: Text(W("Pull down to refresh the list.")))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            ForEach(filtered) { server in
                                VStack(spacing: 12) {
                                NavigationLink(value: server) { ServerCard(server: server, api: store.api, iconEnabled: store.api.map { workspace.isMinecraft($0, server) && !$0.demo && !isBedrockOnly(server) } ?? false, iconRevision: iconRevision, presence: store.presence[server.id], favorite: store.api.map { workspace.favorites.contains(workspace.key($0, server)) } ?? false) }.buttonStyle(.plain).accessibilityIdentifier("server-\(server.id)").contextMenu {
                                    if let api = store.api { Button(workspace.favorites.contains(workspace.key(api, server)) ? W("Unpin server") : W("Pin server"), systemImage: "star") { workspace.toggleServer(api, server) } }
                                }
                                }
                            }
                        }
        }
    }
    @ViewBuilder func homeCard(_ card: DashboardCard, api: PanelAPI) -> some View {
        switch card {
        case .welcome: hero
        case .folders: pinnedFolders(api)
        case .servers: serverList
        case .fleet:
            VStack(alignment: .leading, spacing: 16) {
                Label(W("Server overview"), systemImage: card.symbol).font(.headline)
                HStack(spacing: 24) {
                    fleetCount("Online", count: store.servers.filter { store.presence[$0.id]?.state == "running" }.count, color: .green)
                    fleetCount("Offline", count: store.servers.filter { store.presence[$0.id]?.state == "offline" }.count, color: .secondary)
                    fleetCount(W("Other"), count: store.servers.filter { !["running", "offline"].contains(store.presence[$0.id]?.state ?? "unknown") }.count, color: .orange)
                }
                Text(W("Status refreshes about every 15 seconds while the home screen is open. Unknown states count under Other.")).font(.caption).foregroundStyle(.secondary)
                if let updated = store.presence.values.map(\.updated).max() { HStack { Text(W("Last response")); Spacer(); Text(updated, style: .time) }.font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).card()
        case .favorites:
            VStack(alignment: .leading, spacing: 14) {
                Label(W("Pinned servers"), systemImage: "star.fill").font(.headline)
                let favorites = filtered.filter { workspace.favorites.contains(workspace.key(api, $0)) }
                ForEach(favorites) { server in
                    NavigationLink(value: server) { HStack { Text(server.name); Spacer(); StatePill(state: store.presence[server.id]?.state ?? "unknown"); Image(systemName: "chevron.right").font(.caption) } }.buttonStyle(.plain)
                }
                if favorites.isEmpty { Text(W("Pin servers using the context menu.")).font(.subheadline).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).card()
        case .account:
            VStack(alignment: .leading, spacing: 14) {
                Label(W("Panel information"), systemImage: card.symbol).font(.headline)
                LabeledContent("Panel", value: store.demo ? "Demo" : store.active?.name ?? "Panel")
                Text(api.base.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                LabeledContent("Server", value: String(store.servers.count))
                NavigationLink(W("Account & security")) { AccountView(api: api) }
            }.frame(maxWidth: .infinity, alignment: .leading).card()
        default: EmptyView()
        }
    }
    func fleetCount(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(count, format: .number).font(.title.bold()).foregroundStyle(color); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder func pinnedFolders(_ api: PanelAPI) -> some View {
        let pins = workspace.folders.filter { pin in pin.panel == api.base.absoluteString && store.servers.contains(where: { $0.id == pin.serverID }) }
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(W("Pinned folders"), systemImage: "pin.fill").font(.headline)
                ForEach(pins) { pin in
                    if let server = store.servers.first(where: { $0.id == pin.serverID }) {
                        NavigationLink { ServerView(api: api, server: server, initialFolder: pin.path) } label: {
                            HStack { Image(systemName: "folder.fill").foregroundStyle(Color.panelAccent); VStack(alignment: .leading) { Text(pin.path); Text(server.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).contextMenu { Button(W("Unpin"), systemImage: "pin.slash") { workspace.toggleFolder(api, server, pin.path) } }
                    }
                }
            }
        }
    }
    var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(W("Your servers, everywhere."), systemImage: "globe.europe.africa.fill").font(.title2.bold())
            Text(W("Console, live resources, files and backups. Connected directly to your panel.")).foregroundStyle(.secondary)
            Button(W("Connect panel"), systemImage: "link") { add = true }.buttonStyle(.glassProminent).controlSize(.large)
            Button(W("Explore with sample data"), systemImage: "sparkles") { store.startDemo() }.buttonStyle(.glass)
            Label(W("API keys stay in this device's keychain."), systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
struct ServerCard: View {
    let server: Server
    var api: PanelAPI? = nil
    var iconEnabled = true
    var iconRevision = 0
    var presence: ServerPresence? = nil
    var favorite = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ServerIconView(api: api, server: server, enabled: iconEnabled, revision: iconRevision)
                Spacer()
                StatePill(state: presence?.state ?? "unknown")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(server.name).font(.title2.bold()).foregroundStyle(.primary); if favorite { Image(systemName: "star.fill").font(.subheadline).foregroundStyle(.orange) } }
                Text(server.data["description"].string.isEmpty ? server.node : server.data["description"].string).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider()
            HStack { Label(server.node, systemImage: "location"); Spacer(); Text(server.id).font(.system(.caption, design: .monospaced)) }.font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
struct AddPanelView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var key = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "link.circle.fill").font(.system(size: 42)).foregroundStyle(Color.panelAccent)
                        Text(W("Connect your panel")).font(.title2.bold())
                        Text(W("Use the HTTPS web address of your Pterodactyl panel.")).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    TextField(W("Name, e.g. My Panel"), text: $name)
                    TextField("https://panel.example.com", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("panelURL")
                    SecureField(W("Client API key (ptlc_…)"), text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("apiKey")
                } header: { Text(W("Credentials")) } footer: { Text(W("In your panel: Account → API Credentials → Create API Key. Use a Client key. Application keys are intended for panel administration.")) }
                Section {
                    Button { connect() } label: { HStack { Spacer(); if busy { ProgressView() }; Text(busy ? W("Checking connection …") : W("Connect")).bold(); Spacer() } }.disabled(busy || url.isEmpty || key.isEmpty)
                } footer: { Text(W("HTTPS only. Credentials are sent only to your panel and stored in the iOS keychain.")) }
            }.panelScreen().navigationTitle(W("Add panel")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(W("Cancel")) { dismiss() }.disabled(busy) } }.errorAlert($error).interactiveDismissDisabled(busy)
        }
    }
    func connect() { busy = true; Task { do { try await store.add(name: name, address: url, key: key); key = ""; dismiss() } catch { self.error = error.localizedDescription }; busy = false } }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("syntaxColors") private var syntaxColors = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("wing.language") private var language = "en"
    @State private var remove: PanelProfile?
    var body: some View {
        NavigationStack {
            Form {
                Section(W("Language")) { Picker(W("App language"), selection: $language) { Text("English").tag("en"); Text("Deutsch").tag("de") } }
                Section(W("Appearance")) { NavigationLink(W("Colors & app icon")) { AppearanceSettingsView() }; Picker("Design", selection: $appearance) { Text(W("System")).tag("system"); Text(W("Dark")).tag("dark"); Text(W("Light")).tag("light") } }
                Section(W("Editor & controls")) { Toggle(W("Syntax colors in text editor"), isOn: $syntaxColors); Toggle(W("Haptic feedback"), isOn: $haptics) }
                Section(W("Widgets & transfers")) { NavigationLink(W("Set up server widgets")) { WidgetSettingsView() }; TransferLink() }
                Section(W("Security")) { Toggle(W("Lock app with Face ID / passcode"), isOn: $store.biometricLock) }
                Section(W("Saved panels")) {
                    ForEach(store.profiles) { p in HStack { VStack(alignment: .leading) { Text(p.name); Text(p.provider.title + " · " + p.url).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(W("Remove"), systemImage: "trash", role: .destructive) { remove = p }.labelStyle(.iconOnly) } }
                    if store.profiles.isEmpty { Text(W("No panels saved yet")).foregroundStyle(.secondary) }
                }
                if let api = store.api { Section("Account") { NavigationLink(W("Account & security")) { AccountView(api: api) } } }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Text(W("Independent community client for Pterodactyl. Features and limits depend on your provider and panel permissions.")).font(.footnote).foregroundStyle(.secondary)
                }
            }.panelScreen().navigationTitle(W("Settings")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { dismiss() } } }
                .confirmationDialog(W("Remove saved connection?"), isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
                    Button(W("Remove connection"), role: .destructive) { if let p = remove { store.remove(p) }; remove = nil }
                } message: { Text(W("The local API key will be deleted. Your server remains.")) }
        }
    }
}

