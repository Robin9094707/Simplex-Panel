import SwiftUI

struct PlayerManagerView: View {
    let api: PanelAPI
    let server: Server
    @ObservedObject var live: LiveServer
    @StateObject private var preferences = PlayerPreferencesStore()
    @State private var search = ""
    @State private var settings = false
    var key: String { api.base.absoluteString + "|" + server.id }
    var names: [String] { Array(Set(live.players?.names ?? [])).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section {
                HStack { Label(W("Online players"), systemImage: "person.2.fill").font(.headline); Spacer(); StatePill(state: live.state) }
                Text(live.players.map { W("\($0.online) of \(($0.maximum ?? live.playerCapacity).map(String.init) ?? "?") online") } ?? W("Waiting for player data …")).font(.title2.bold()).monospacedDigit()
                if let snapshot = live.players { LabeledContent(W("Snapshot")) { Text(snapshot.updated, style: .time) }; Text(snapshot.source).font(.caption).foregroundStyle(.secondary) }
                if let issue = live.playerIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                Button(W("Refresh players"), systemImage: "arrow.clockwise") { Task { await live.refreshPlayers(api: api, server: server) } }
            }
            Section(W("Players · \(names.count)")) {
                ForEach(names, id: \.self) { name in
                    NavigationLink {
                        PlayerDetailView(api: api, server: server, live: live, name: name, preferences: preferences, key: key)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(name.hasPrefix(".") ? .blue : .teal)
                            VStack(alignment: .leading, spacing: 4) { Text(name).font(.headline); Text(W("Live values & actions")).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("managePlayer-" + name)
                }
                if names.isEmpty { Text(live.players?.online == 0 ? W("Nobody online right now") : W("No player names available. Refresh the list or check the list command in the console.")).foregroundStyle(.secondary) }
            }
        }.panelScreen().navigationTitle(W("Player manager")).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: W("Search players"))
            .task { await live.refreshPlayers(api: api, server: server) }
            .refreshable { await live.refreshPlayers(api: api, server: server) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(W("Player commands"), systemImage: "slider.horizontal.3") { settings = true } } }
            .sheet(isPresented: $settings) { PlayerCommandSettings(preferences: preferences, key: key) }
    }
}
struct PlayerCommandRequest: Identifiable {
    let id = UUID()
    var title: String
    var template: String
    var needsReason = false
    var destructive = false
}
struct PlayerDetailView: View {
    let api: PanelAPI
    let server: Server
    @ObservedObject var live: LiveServer
    let name: String
    @ObservedObject var preferences: PlayerPreferencesStore
    let key: String
    @StateObject private var inspector = PlayerInspector()
    @State private var automatic = false
    @State private var mode = "survival"
    @State private var level = 0
    @State private var initializedControls = false
    @State private var request: PlayerCommandRequest?
    @State private var notice: String?
    var online: Bool { live.state == "running" && live.players?.names.contains(name) == true }
    var commands: PlayerCommandPreferences { preferences.get(key) }
    var body: some View {
        List {
            Section {
                HStack { Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Color.panelAccent); VStack(alignment: .leading, spacing: 4) { Text(name).font(.title2.bold()).textSelection(.enabled); Label(online ? "Online" : W("Last seen / offline"), systemImage: online ? "circle.fill" : "circle").font(.caption).foregroundStyle(online ? Color.green : .secondary) } }
                Button(W("Copy player name"), systemImage: "doc.on.doc") { Clipboard.copy(name) }
            }
            Section {
                HStack { Label(W("Live values"), systemImage: "waveform.path.ecg").font(.headline); Spacer(); if inspector.busy { ProgressView() } }
                if let health = PlayerCommands.number(inspector.values["Health"]) { LabeledContent { Text(String(format: W("%.1f hearts · %.1f HP"), health / 2, health)).monospacedDigit() } label: { Label(W("Health"), systemImage: "heart.fill").foregroundStyle(.pink) } }
                else { LabeledContent(W("Health"), value: "–") }
                LabeledContent(W("Hunger"), value: PlayerCommands.number(inspector.values["foodLevel"]).map { "\(Int($0)) / 20" } ?? "–")
                LabeledContent(W("Experience level"), value: PlayerCommands.number(inspector.values["XpLevel"]).map { String(Int($0)) } ?? "–")
                LabeledContent(W("Game mode"), value: gameModeName)
                if let position = inspector.values["Pos"] { LabeledContent("Position", value: position).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                if let dimension = inspector.values["Dimension"] { LabeledContent("Dimension", value: dimension.replacingOccurrences(of: "\"", with: "")) }
                if let updated = inspector.updated { LabeledContent(W("Full query")) { Text(updated, style: .time) } }
                if let issue = inspector.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                Button(W("Load values"), systemImage: "arrow.clockwise") { Task { await read() } }.disabled(inspector.busy || !online).requiresAccess(api, server.id, "control.console", "websocket.connect")
                Toggle(W("Query every 15 seconds"), isOn: $automatic).disabled(!online)
            } footer: { Text(W("Values are read using targeted data-get commands in the live console. Automatic queries are optional and produce console output. Suppressed or translated output may prevent detection.")) }
            Section(W("Change on the running server")) {
                Picker(W("Game mode"), selection: $mode) { Text(W("Survival")).tag("survival"); Text(W("Creative")).tag("creative"); Text(W("Adventure")).tag("adventure"); Text(W("Spectator")).tag("spectator") }
                Button(W("Apply game mode")) { request = PlayerCommandRequest(title: W("Change game mode"), template: "minecraft:gamemode " + mode + " {player}") }
                TextField(W("Experience level"), value: $level, format: .number).keyboardType(.numberPad)
                Button(W("Apply experience level")) { request = PlayerCommandRequest(title: W("Set experience level"), template: "minecraft:experience set {player} \(level) levels") }.disabled(!(0...10000).contains(level))
                Button(W("Instant healing"), systemImage: "heart.fill") { request = PlayerCommandRequest(title: W("Instant healing"), template: "minecraft:effect give {player} minecraft:instant_health 1 4 true") }
                Button(W("Saturate"), systemImage: "carrot.fill") { request = PlayerCommandRequest(title: W("Saturate player"), template: "minecraft:effect give {player} minecraft:saturation 1 10 true") }
            }.disabled(!online).requiresAccess(api, server.id, "control.console")
            Section(W("Moderation & custom actions")) {
                Button(W("Kick"), systemImage: "person.crop.circle.badge.xmark", role: .destructive) { request = PlayerCommandRequest(title: W("Kick player"), template: commands.kick, needsReason: true, destructive: true) }
                Button(W("Ban"), systemImage: "hand.raised.fill", role: .destructive) { request = PlayerCommandRequest(title: W("Ban player"), template: commands.ban, needsReason: true, destructive: true) }
                ForEach(commands.custom) { action in Button(action.name, systemImage: "terminal") { request = PlayerCommandRequest(title: action.name, template: action.command, needsReason: action.command.contains("{reason}"), destructive: true) } }
            }.disabled(!online).requiresAccess(api, server.id, "control.console")
            Section { Text(W("Online changes use server commands shown before sending. Arbitrary player NBT fields require a suitable server plugin; edit saved player files only while offline.")).font(.caption).foregroundStyle(.secondary) }
        }.panelScreen().navigationTitle(name).navigationBarTitleDisplayMode(.inline)
            .task(id: automatic) {
                await read()
                if automatic { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(15)) } catch { return }; await read() } }
            }
            .refreshable { await live.refreshPlayers(api: api, server: server); await read() }
            .sheet(item: $request) { action in PlayerCommandSheet(api: api, server: server, live: live, player: name, action: action) { notice = W("Command sent to the server. The result appears in the console."); Task { await live.refreshPlayers(api: api, server: server); if !action.destructive { await read() } } } }
            .alert(W("Command submitted"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK") { notice = nil } } message: { Text(notice ?? "") }
    }
    var gameModeName: String { guard let mode = PlayerCommands.number(inspector.values["playerGameType"]), (0...3).contains(mode) else { return "–" }; return [W("Survival"), W("Creative"), W("Adventure"), W("Spectator")][Int(mode)] }
    func read() async { await inspector.read(player: name, live: live, api: api, server: server); guard !initializedControls, inspector.updated != nil else { return }; initializedControls = true; if let value = PlayerCommands.number(inspector.values["XpLevel"]), (0...10000).contains(value) { level = Int(value) }; if let value = PlayerCommands.number(inspector.values["playerGameType"]), (0...3).contains(value) { mode = ["survival", "creative", "adventure", "spectator"][Int(value)] } }
}
struct PlayerCommandSheet: View {
    let api: PanelAPI
    let server: Server
    @ObservedObject var live: LiveServer
    let player: String
    let action: PlayerCommandRequest
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = W("Please follow the server rules.")
    @State private var busy = false
    @State private var error: String?
    var command: String? { try? PlayerCommands.render(action.template, player: player, reason: reason) }
    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent(W("Players"), value: player); if action.needsReason { TextField(W("Reason"), text: $reason, axis: .vertical) } }
                Section(W("Review command before sending")) { Text(command ?? W("Invalid template. Adjust it under Player commands.")).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                if action.destructive { Text(W("This action may disconnect the player or change game state. Exactly the displayed command will be sent.")).font(.footnote).foregroundStyle(.orange) }
                Button(action.destructive ? W("Confirm & run") : W("Run command"), role: action.destructive ? .destructive : nil) { send() }.disabled(command == nil || busy || live.state != "running").requiresAccess(api, server.id, "control.console")
            }.panelScreen().navigationTitle(action.title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button(W("Cancel")) { dismiss() }.disabled(busy) } }.errorAlert($error).interactiveDismissDisabled(busy)
        }
    }
    func send() { guard let command else { return }; busy = true; Task { defer { busy = false }; do { try await live.sendCommand(command, api: api, server: server); done(); dismiss() } catch { self.error = error.localizedDescription } } }
}
struct PlayerCommandSettings: View {
    @ObservedObject var preferences: PlayerPreferencesStore
    let key: String
    @Environment(\.dismiss) private var dismiss
    @State private var value: PlayerCommandPreferences
    @State private var error: String?
    init(preferences: PlayerPreferencesStore, key: String) { self.preferences = preferences; self.key = key; _value = State(initialValue: preferences.get(key)) }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(W("Templates are stored only for this server on your device. {player} is replaced by the exact name, including any Bedrock prefix. {reason} is the entered reason. Example: litebans:ban {player} {reason}")).font(.footnote).foregroundStyle(.secondary) }
                Section("Moderation") { TextField(W("Kick command"), text: $value.kick, axis: .vertical); TextField(W("Ban command"), text: $value.ban, axis: .vertical) }.font(.system(.subheadline, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never)
                Section(W("Custom actions")) {
                    ForEach($value.custom) { $action in VStack(alignment: .leading) { TextField(W("Action name"), text: $action.name); TextField(W("Command with {player}"), text: $action.command, axis: .vertical).font(.system(.subheadline, design: .monospaced)); Button(W("Remove action"), role: .destructive) { let id = action.id; value.custom.removeAll { $0.id == id } }.font(.caption) } }
                    if value.custom.count < 20 { Button(W("Add action"), systemImage: "plus") { value.custom.append(PlayerActionTemplate(name: "", command: "")) } }
                }.autocorrectionDisabled().textInputAutocapitalization(.never)
            }.panelScreen().navigationTitle(W("Player commands")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(W("Cancel")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(W("Save")) { save() } } }.errorAlert($error)
        }
    }
    func save() { do {
        _ = try PlayerCommands.render(value.kick, player: ".Bedrock_Player", reason: W("Reason"))
        _ = try PlayerCommands.render(value.ban, player: "Java_Player", reason: W("Reason"))
        for action in value.custom { guard !action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PanelError(message: W("Give every action a name.")) }; _ = try PlayerCommands.render(action.command, player: "Java_Player", reason: W("Reason")) }
        preferences.save(value, key: key); dismiss()
    } catch { self.error = error.localizedDescription } }
}

