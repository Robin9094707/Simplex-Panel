import SwiftUI
import Charts

struct ServerView: View {
    let api: PanelAPI
    private let initialServer: Server
    var server: Server { store.servers.first { $0.id == initialServer.id } ?? initialServer }
    let initialFolder: String?
    init(api: PanelAPI, server: Server, initialFolder: String? = nil) {
        self.api = api; self.initialServer = server; self.initialFolder = initialFolder
        _tab = State(initialValue: initialFolder == nil ? 0 : 2)
    }
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var commandLibrary = false
    @State private var refreshing = false
    @StateObject private var live = LiveServer()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var operation: Operation?
    @State private var error: String?
    @State private var command = ""
    @State private var sending = false
    @State private var follow = true
    @State private var filter = ""
    @State private var fontSize = 12.0
    @ObservedObject private var layouts = DashboardLayouts.shared
    @ObservedObject private var consoleHistory = ConsoleHistory.shared
    @State private var editLayout = false
    @State private var iconRevision = 0
    @State private var historySheet = false
    @State private var historyCursor = CommandHistoryCursor()
    @StateObject private var viewport = ConsoleViewportState()
    @StateObject private var consoleProjection = ConsoleProjection()
    @State private var consoleCategory = ConsoleCategory.all
    @State private var consoleEpoch = 0
    var consoleText: String { consoleProjection.result.text }
    @State private var frozen = false
    @State private var frozenLines: [String] = []
    @State private var jumpRevision = 0
    var body: some View {
        TabView(selection: $tab) {
            Tab(W("Overview"), systemImage: "gauge.with.dots.needle.67percent", value: 0) { overview }
            Tab(W("Console"), systemImage: "terminal", value: 1) { AccessBoundary(access: api.access, server: server.id, permission: "websocket.connect") { console } }
            Tab(W("Files"), systemImage: "folder", value: 2) { AccessBoundary(access: api.access, server: server.id, permission: "file.read") { FilesView(api: api, server: server, root: initialFolder ?? "/") } }
            Tab(W("More"), systemImage: "ellipsis", value: 4) {
                List {
                    NavigationLink("Backups") { AccessBoundary(access: api.access, server: server.id, permission: "backup.read") { BackupsView(api: api, server: server) } }
                    NavigationLink(W("Manage")) { ManageView(api: api, server: server, live: live) }
                    NavigationLink(W("Server Live Activity")) { ServerActivitySettings(api: api, server: server, live: live) }
                }.panelScreen()
            }
        }.navigationTitle(server.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(W("Customize workspace"), systemImage: "rectangle.3.group") { editLayout = true }.accessibilityIdentifier("editServerLayout") }; ToolbarItem(placement: .topBarTrailing) { Button(W("Refresh server"), systemImage: "arrow.clockwise") { Task { await refreshServer() } } }; ToolbarItem(placement: .topBarTrailing) { powerMenu } }
            .task(id: "\(scenePhase)-\(workspace.isMinecraft(api, server))") {
                if scenePhase == .active {
                    await api.loadAccess(server: server.id)
                    guard !Task.isCancelled else { return }
                    await live.run(api: api, server: server, minecraft: workspace.isMinecraft(api, server))
                }
            }
            .onChange(of: tab) { _, value in if value == 1 { updateConsoleText() } else { consoleProjection.stop() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active && tab == 1 { updateConsoleText() } else if phase != .active { consoleProjection.stop() } }
            .onChange(of: live.lastUpdate) { _, _ in publishStatus() }
            .onChange(of: live.players) { _, _ in publishStatus() }
            .onChange(of: live.state) { _, state in store.presence[server.id] = ServerPresence(state: state) }
            .sheet(isPresented: $editLayout) { DashboardEditor(scope: .server, layoutKey: layoutKey) }
            .sheet(isPresented: $historySheet) { ConsoleHistorySheet(historyKey: historyKey) { command = $0; historyCursor = CommandHistoryCursor(); tab = 1 } }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) }
            .sheet(isPresented: $commandLibrary) { CommandLibrary(api: api, server: server) { command = $0 } }
            .errorAlert($error)
    }
    func publishStatus() {
        WidgetPublisher.publish(api: api, server: server, live: live)
        ServerActivityManager.shared.publish(api: api, server: server, live: live)
    }
    var powerMenu: some View {
        Menu {
            Button(W("Start"), systemImage: "play.fill") { power("start", title: W("Start server")) }.disabled(!PowerPolicy.allows("start", state: live.state)).requiresAccess(api, server.id, "control.start")
            Button(W("Restart"), systemImage: "arrow.clockwise") { power("restart", title: W("Restart server"), destructive: true) }.disabled(!PowerPolicy.allows("restart", state: live.state)).requiresAccess(api, server.id, "control.restart")
            Button(W("Stop"), systemImage: "stop.fill", role: .destructive) { power("stop", title: W("Stop server"), destructive: true) }.disabled(!PowerPolicy.allows("stop", state: live.state)).requiresAccess(api, server.id, "control.stop")
            Button(W("Force stop"), systemImage: "bolt.slash", role: .destructive) { power("kill", title: W("Force stop"), destructive: true) }.disabled(!PowerPolicy.allows("kill", state: live.state)).requiresAccess(api, server.id, "control.stop")
        } label: { Image(systemName: "power").foregroundStyle(Color.panelAccent).accessibilityLabel(W("Power controls")) }
    }
    func power(_ signal: String, title: String, destructive: Bool = false) {
        operation = Operation(title: title, detail: signal == "kill" ? W("The process ends immediately. Unsaved data may be lost.") : W("The action will run for \(server.name)."), path: "servers/\(server.id)/power", fixed: ["signal": .string(signal)], destructive: destructive, submit: W("Run"))
    }
    var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(layouts.cards(layoutKey, scope: .server)) { card in overviewCard(card) }
            }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.panelScreen().refreshable { await refreshServer() }.scrollBounceBehavior(.always)
    }
    var layoutKey: String { "server:" + api.base.absoluteString + "|" + (api.demo ? "demo:" : "") + server.id }
    var historyKey: String { workspace.key(api, server) }
    var commandEntries: [String] { consoleHistory.entries(historyKey) }
    @ViewBuilder func overviewCard(_ card: DashboardCard) -> some View {
        switch card {
        case .identity: identityCard
        case .players: playersSection
        case .resources: resourceCards
        case .cpuHistory: cpuCard
        case .network: networkCard
        case .health: healthCard
        case .memoryHistory: memoryCard
        case .shortcuts:
            VStack(alignment: .leading, spacing: 14) {
                Label(W("Console shortcuts"), systemImage: "terminal").font(.headline)
                Button(W("Open console"), systemImage: "terminal") { tab = 1 }.buttonStyle(.glass)
                Button(W("Command history"), systemImage: "clock.arrow.circlepath") { historySheet = true }
                ForEach(workspace.shortcuts[workspace.key(api, server)] ?? []) { shortcut in
                    Button(shortcut.name) { command = shortcut.command; tab = 1 }
                }
                Text(W("Shortcuts open in the input field before sending.")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).card()
        default: EmptyView()
        }
    }
    var identityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack { ServerIconView(api: api, server: server, enabled: workspace.isMinecraft(api, server) && !server.data["invocation"].string.lowercased().contains("bedrock_server") && !server.data["container"]["image"].string.lowercased().contains("bedrock"), revision: iconRevision); VStack(alignment: .leading, spacing: 8) { Text(server.name).font(.largeTitle.bold()); Text(server.address).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }; Spacer(); StatePill(state: live.state) }
                HStack(spacing: 7) { Circle().fill(live.connected ? Color.green : Color.orange).frame(width: 6, height: 6); Text(live.connection); Spacer(); if let updated = live.lastUpdate { Text(updated, style: .time).monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
                if let issue = live.issue, !live.connected { Label(issue, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange).card() }
                AccessSummary(access: api.access, api: api, server: server.id)
                Toggle(W("Minecraft player overview"), isOn: Binding(get: { workspace.isMinecraft(api, server) }, set: { workspace.setMinecraft($0, api, server) })).font(.subheadline)
        }
    }
    @ViewBuilder var playersSection: some View {
                if workspace.isMinecraft(api, server) {
                    PlayersCard(live: live, api: api, server: server)
                    TPSCard(live: live, api: api, server: server)
                }
                if server.data["is_suspended"].bool || server.data["is_installing"].bool || server.data["is_node_under_maintenance"].bool {
                    Label(server.data["is_suspended"].bool ? W("Server is suspended") : server.data["is_installing"].bool ? W("Installation in progress") : W("Node under maintenance"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange).card()
                }
    }
    var resourceCards: some View {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 14)], spacing: 14) {
                    MetricCard(title: W("Memory"), symbol: "memorychip", value: live.stats["memory_bytes"] == .null ? "–" : bytes(live.memory), limit: limitBytes("memory"), fraction: live.lastUpdate == nil ? nil : fraction(live.memory, "memory"), tint: Color.panelAccent)
                    MetricCard(title: "CPU", symbol: "cpu", value: live.stats["cpu_absolute"] == .null ? "–" : String(format: "%.1f %%", live.cpu), limit: server.data["limits"]["cpu"].double > 0 ? W("of \(server.data["limits"]["cpu"].string) %") : W("Unlimited"), fraction: live.lastUpdate == nil ? nil : ResourceLoad.fraction(value: live.cpu, limit: server.data["limits"]["cpu"].double), tint: Color.panelSecondary)
                    MetricCard(title: W("Disk space"), symbol: "internaldrive", value: live.lastUpdate == nil ? "–" : bytes(live.disk), limit: limitBytes("disk"), fraction: live.lastUpdate == nil ? nil : fraction(live.disk, "disk"), tint: .blue)
                    MetricCard(title: W("Uptime"), symbol: "clock", value: live.stats["uptime"] == .null ? "–" : Duration.seconds(live.uptime).formatted(.time(pattern: .hourMinuteSecond)), limit: live.state == "offline" ? W("Server is offline") : W("since last start"), fraction: nil, tint: .orange)
                }
    }
    var cpuCard: some View {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text(W("CPU history")).font(.headline); Spacer(); Text(W("Live · last 120 samples")).font(.caption).foregroundStyle(.secondary) }
                    if live.history.isEmpty { ContentUnavailableView(W("Waiting for metrics"), systemImage: "waveform.path.ecg").frame(height: 150) }
                    else {
                        Chart(live.history) { point in
                            AreaMark(x: .value(W("Time"), point.date), y: .value("CPU", point.cpu)).foregroundStyle(LinearGradient(colors: [.teal.opacity(0.25), .teal.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                            LineMark(x: .value(W("Time"), point.date), y: .value("CPU", point.cpu)).foregroundStyle(Color.panelAccent).interpolationMethod(.catmullRom)
                        }.chartYScale(domain: 0...max(100, (live.history.map(\.cpu).max() ?? 100) * 1.1)).chartXAxis(.hidden).frame(height: 150).accessibilityLabel(W("CPU history"))
                    }
                }.card()
    }
    var networkCard: some View {
                VStack(alignment: .leading, spacing: 16) {
                    Text(W("Network & connection")).font(.headline)
                    LabeledContent(W("Received"), value: bytes(live.stats["network"]["rx_bytes"].double))
                    LabeledContent(W("Sent"), value: bytes(live.stats["network"]["tx_bytes"].double))
                    LabeledContent("Node", value: server.node)
                    Text(W("CPU: 100% equals one CPU core. The panel reports RAM and disk limits in MiB.")).font(.caption).foregroundStyle(.secondary)
                }.card()
    }
    var healthCard: some View {
        let fractions = [fraction(live.memory, "memory"), ResourceLoad.fraction(value: live.cpu, limit: server.data["limits"]["cpu"].double), fraction(live.disk, "disk")]
        let health = ServerHealth.assess(state: live.state, updated: live.lastUpdate, fractions: fractions)
        return VStack(alignment: .leading, spacing: 14) {
            Label(W("Server health"), systemImage: "heart.text.square").font(.headline)
            Label(health.title, systemImage: health.level == .high ? "exclamationmark.triangle.fill" : health.level == .unknown ? "questionmark.circle" : "checkmark.circle.fill").foregroundStyle(health.level.color)
            Text(health.detail).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Status", value: live.state)
            if let date = live.lastUpdate { LabeledContent(W("Last metric")) { Text(date, style: .relative) } }
            if let tps = live.tps, Date().timeIntervalSince(tps.updated) <= 75 {
                LabeledContent(W("TPS · 1 minute")) { Text(tps.minute, format: .number.precision(.fractionLength(2))).foregroundStyle(TPSSnapshot.color(tps.minute)) }
            }
            if let issue = live.issue { Label(issue, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
    var memoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(W("RAM history")).font(.headline); Spacer(); Text(W("Live · last 120 samples")).font(.caption).foregroundStyle(.secondary) }
            if live.history.isEmpty { ContentUnavailableView(W("Waiting for metrics"), systemImage: "memorychip").frame(height: 150) }
            else {
                Chart(live.history) { point in
                    AreaMark(x: .value(W("Time"), point.date), y: .value("RAM · GiB", point.memory / 1_073_741_824)).foregroundStyle(.teal.opacity(0.16))
                    LineMark(x: .value(W("Time"), point.date), y: .value("RAM · GiB", point.memory / 1_073_741_824)).foregroundStyle(Color.panelAccent)
                }.chartYScale(domain: .automatic(includesZero: true)).chartXAxis(.hidden).frame(height: 150).accessibilityLabel(W("RAM history in GiB"))
            }
        }.card()
    }
    func refreshServer() async {
        guard !refreshing else { return }; iconRevision += 1; refreshing = true; defer { refreshing = false }
        // Independent sources start together; slow workspace lists do not block live stats.
        async let access: Void = api.loadAccess(server: server.id)
        async let workspaceRefresh: Void = store.refresh()
        do { try await live.refresh(api: api, server: server, minecraft: workspace.isMinecraft(api, server)) }
        catch { if !RequestFailure.isCancellation(error) && !Task.isCancelled { self.error = error.localizedDescription } }
        _ = await (access, workspaceRefresh)
    }
    func limitBytes(_ key: String) -> String { let limit = server.data["limits"][key].double; return limit > 0 ? W("of ") + bytes(limit * 1_048_576) : W("Unlimited") }
    func fraction(_ value: Double, _ key: String) -> Double? { let limit = server.data["limits"][key].double; return ResourceLoad.fraction(value: value, limit: limit * 1_048_576) }
    var console: some View {
        VStack(spacing: 0) {
            HStack {
                Label(live.connected ? W("Live console") : W("Disconnected"), systemImage: live.connected ? "dot.radiowaves.left.and.right" : "wifi.slash").font(.caption).foregroundStyle(live.connected ? Color.teal : Color.orange)
                Spacer()
                Menu {
                    ForEach(ConsoleCategory.allCases) { category in
                        Button(category.title, systemImage: consoleCategory == category ? "checkmark" : category.symbol) { consoleCategory = category }
                            .accessibilityIdentifier("console-category-" + category.rawValue)
                            .accessibilityValue(consoleCategory == category ? W("Selected") : "")
                    }
                } label: { Image(systemName: consoleCategory == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill").padding(6) }
                    .accessibilityLabel(W("Console filters")).accessibilityIdentifier("consoleFilterMenu")
                Menu {
                    Toggle(W("Auto-scroll"), isOn: $follow)
                    Toggle(W("Pause output"), isOn: $frozen)
                    Button(W("Jump to bottom"), systemImage: "arrow.down.to.line") { jumpRevision += 1 }
                    Button(W("Command history"), systemImage: "clock.arrow.circlepath") { historySheet = true }
                    Button(W("Copy filtered output"), systemImage: "doc.on.doc") { Clipboard.copy(cleanConsole(consoleText)) }
                    Button(W("Increase font size")) { fontSize = min(22, fontSize + 1) }
                    Button(W("Decrease font size")) { fontSize = max(10, fontSize - 1) }
                    Button(W("Clear display"), role: .destructive) { live.clearConsole(); frozenLines = []; consoleEpoch += 1; updateConsoleText() }
                } label: { Image(systemName: "ellipsis.circle").padding(6) }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            HStack {
                TextField(W("Search output"), text: $filter).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("consoleSearch")
                if !filter.isEmpty { Button(W("Clear search"), systemImage: "xmark.circle.fill") { filter = "" }.labelStyle(.iconOnly) }
            }.padding(.horizontal, 16).padding(.bottom, 4)
            HStack { Label(consoleCategory.title, systemImage: consoleCategory.symbol); Spacer(); Text(W("\(consoleProjection.result.shown) / \(consoleProjection.result.total) lines")).monospacedDigit() }
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
            ConsoleTextView(text: consoleText, fontSize: fontSize, follow: follow && !frozen, viewport: viewport, active: scenePhase == .active, jumpRevision: jumpRevision, refresh: { await refreshServer() })
                .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1).background(.black.opacity(0.08))
            if frozen { Label(W("Display paused · live output continues in background"), systemImage: "pause.circle").font(.caption).foregroundStyle(.orange).padding(8) }
            HStack(spacing: 8) {
                Button(W("Older command"), systemImage: "arrow.up") { previousCommand() }.disabled(commandEntries.isEmpty).accessibilityIdentifier("history-older")
                Button(W("Newer command"), systemImage: "arrow.down") { nextCommand() }.disabled(historyCursor.index == nil).accessibilityIdentifier("history-newer")
                Button(W("Command history"), systemImage: "clock.arrow.circlepath") { historySheet = true }.accessibilityIdentifier("consoleHistory")
                Button(W("Jump to bottom"), systemImage: "arrow.down.to.line") { jumpRevision += 1 }.accessibilityIdentifier("consoleEnd")
                Button(frozen ? W("Resume output") : W("Pause output"), systemImage: frozen ? "play.fill" : "pause.fill") { frozen.toggle() }.accessibilityIdentifier("consolePause")
                Button(W("Command shortcuts"), systemImage: "bolt") { commandLibrary = true }.accessibilityIdentifier("consoleShortcuts")
            }.labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.regular)
                .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 8)
            if workspace.isMinecraft(api, server) && !command.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(CommandLibrary.suggestions.filter { $0.hasPrefix(command.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) && $0 != command }.prefix(4)), id: \.self) { suggestion in
                            Button(suggestion) { command = suggestion }.buttonStyle(.glass)
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 6)
                }.accessibilityLabel(W("Command suggestions"))
            }
            HStack(spacing: 12) {
                Text(">").font(.system(.body, design: .monospaced)).foregroundStyle(Color.panelAccent)
                TextField(W("Enter command …"), text: $command).font(.system(.body, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.send).onSubmit(sendCommand).onKeyPress(.upArrow) { previousCommand(); return .handled }.onKeyPress(.downArrow) { nextCommand(); return .handled }.accessibilityIdentifier("consoleCommand").requiresAccess(api, server.id, "control.console")
                Button(action: sendCommand) { if sending { ProgressView() } else { Image(systemName: "arrow.up").fontWeight(.bold) } }.buttonStyle(.glassProminent).disabled(sending || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !live.connected).accessibilityLabel(W("Send command")).requiresAccess(api, server.id, "control.console")
            }.padding(16).background(.bar)
        }.onAppear { updateConsoleText() }.onDisappear { consoleProjection.stop() }
            .onChange(of: live.logRevision) { _, _ in if !frozen { updateConsoleText() } }
            .onChange(of: filter) { _, _ in updateConsoleText() }
            .onChange(of: consoleCategory) { _, _ in updateConsoleText() }
            .onChange(of: frozen) { _, paused in consoleEpoch += 1; if paused { frozenLines = live.lines }; updateConsoleText() }
            .onChange(of: command) { _, text in historyCursor.edited(text) }
            .background { PanelBackground() }.safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 1) }
    }
    func updateConsoleText() {
        guard tab == 1, scenePhase == .active else { return }
        consoleProjection.request(frozen ? frozenLines : live.lines, category: consoleCategory, query: filter, context: consoleEpoch)
    }
    func previousCommand() { command = historyCursor.older(current: command, entries: commandEntries) }
    func nextCommand() { guard historyCursor.index != nil else { return }; command = historyCursor.newer(entries: commandEntries) }
    func sendCommand() {
        var text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if workspace.isMinecraft(api, server) && text.hasPrefix("/") { text.removeFirst() }
        guard !text.isEmpty, !sending else { return }
        sending = true
        Task { do {
            guard !api.demo else { throw PanelError(message: W("Commands are not sent in demo mode.")) }
            try await live.sendCommand(text, api: api, server: server); consoleHistory.remember(text, key: historyKey); command = ""; historyCursor = CommandHistoryCursor(); Feedback.success()
        } catch { self.error = error.localizedDescription }; sending = false }
    }
}
struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let limit: String
    let fraction: Double?
    let tint: Color
    var metricColor: Color { fraction == nil ? tint : ResourceLoad.level(fraction).color }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(metricColor)
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1).contentTransition(.numericText())
            Text(limit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let fraction { ProgressView(value: min(1, max(0, fraction))).tint(metricColor).accessibilityLabel(title + " · " + ResourceLoad.level(fraction).title) }
            else { Capsule().fill(tint.opacity(0.14)).frame(height: 4) }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}


