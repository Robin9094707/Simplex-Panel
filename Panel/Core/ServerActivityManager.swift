import SwiftUI
import ActivityKit
import UIKit

@MainActor final class ServerActivityManager: ObservableObject {
    static let shared = ServerActivityManager()
    @Published private(set) var activity: Activity<ServerActivity>? = Activity<ServerActivity>.activities.first
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var lastPublish = Date.distantPast
    private var generation = UUID()
    func matches(_ api: PanelAPI, _ server: Server) -> Bool { activity?.attributes.panel == api.base.absoluteString && activity?.attributes.serverID == server.id && activity?.activityState != .ended && activity?.activityState != .dismissed }
    func snapshot(live: LiveServer) -> ServerActivity.ContentState {
        ServerActivity.ContentState(state: live.state, cpu: PanelNumbers.number(live.stats["cpu_absolute"]), memory: PanelNumbers.number(live.stats["memory_bytes"]), online: live.players?.online, maximum: live.players?.maximum, tps: live.tps?.minute, uptime: PanelNumbers.number(live.stats["uptime"]).map { $0 / 1000 }, updated: live.lastUpdate ?? .distantPast, playersUpdated: live.players?.updated, performanceUpdated: live.tps?.updated, source: "Panel", issue: live.issue)
    }
    func start(api: PanelAPI, server: Server, live: LiveServer) async {
        guard UIApplication.shared.applicationState == .active else { error = W("Open the app to start the Live Activity."); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { error = W("Live Activities are disabled in iOS Settings."); return }
        await stop()
        do {
            let state = snapshot(live: live)
            activity = try Activity.request(attributes: ServerActivity(panel: api.base.absoluteString, serverID: server.id, name: server.name), content: ActivityContent(state: state, staleDate: state.updated.addingTimeInterval(90)), pushType: nil)
            error = nil; resume(api: api, servers: [server])
        } catch { self.error = error.localizedDescription }
    }
    func stop() async {
        generation = UUID(); task?.cancel(); task = nil
        let old = activity; activity = nil
        for item in Activity<ServerActivity>.activities { await item.end(nil, dismissalPolicy: .immediate) }
        if let old, !Activity<ServerActivity>.activities.contains(where: { $0.id == old.id }) { await old.end(nil, dismissalPolicy: .immediate) }
    }
    func suspend() { generation = UUID(); task?.cancel(); task = nil }
    func resume(api: PanelAPI?, servers: [Server]) {
        task?.cancel(); task = nil; generation = UUID()
        activity = Activity<ServerActivity>.activities.first { $0.activityState == .active || $0.activityState == .stale }
        guard let api, let activity, activity.attributes.panel == api.base.absoluteString, let server = servers.first(where: { $0.id == activity.attributes.serverID }) else { return }
        let id = generation
        task = Task {
            while !Task.isCancelled && generation == id {
                await poll(api: api, server: server, generation: id)
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            }
        }
    }
    func publish(api: PanelAPI, server: Server, live: LiveServer) {
        guard matches(api, server), Date().timeIntervalSince(lastPublish) >= 10, let activity else { return }
        lastPublish = Date()
        let state = snapshot(live: live)
        let content = ActivityContent(state: state, staleDate: state.updated.addingTimeInterval(90))
        Task { await activity.update(content) }
    }
    private func poll(api: PanelAPI, server: Server, generation id: UUID) async {
        guard let activity, matches(api, server) else { return }
        do {
            let resource = try await api.request("servers/\(server.id)/resources").attributes
            var state = activity.content.state
            state.state = resource["current_state"].string
            let stats = resource["resources"]
            state.cpu = PanelNumbers.number(stats["cpu_absolute"]); state.memory = PanelNumbers.number(stats["memory_bytes"])
            state.uptime = PanelNumbers.number(stats["uptime"]).map { $0 / 1000 }; state.updated = Date(); state.issue = nil
            if state.state == "offline" { state.online = 0; state.playersUpdated = Date(); state.tps = nil; state.mspt = nil }
            guard !Task.isCancelled, generation == id, self.activity?.id == activity.id else { return }
            await activity.update(ActivityContent(state: state, staleDate: state.updated.addingTimeInterval(90)))
        } catch {
            guard !Task.isCancelled, generation == id else { return }
            var state = activity.content.state; state.issue = error.localizedDescription
            await activity.update(ActivityContent(state: state, staleDate: state.updated.addingTimeInterval(90)))
        }
    }
}

struct ServerActivitySettings: View {
    let api: PanelAPI
    let server: Server
    @ObservedObject var live: LiveServer
    @ObservedObject private var manager = ServerActivityManager.shared
    var body: some View {
        Form {
            Section(server.name) {
                Label(W("Server on Lock Screen & Dynamic Island"), systemImage: "waveform.path.ecg").font(.headline)
                Text(W("Players, CPU, RAM and uptime. One server can be selected at a time."))
                if manager.matches(api, server) { Button(W("End Live Activity"), systemImage: "stop.circle", role: .destructive) { Task { await manager.stop() } } }
                else { Button(W("Start Live Activity"), systemImage: "play.circle") { Task { await manager.start(api: api, server: server, live: live) } } }
            }
            Section(W("Refresh")) {
                Text(W("While the app is active, values refresh about every 20 seconds, including when you visit another screen. In the background, the last snapshot stays visible and is marked outdated after 90 seconds."))
                Text(W("iOS limits Live Activities to about eight hours. Continuous updates with the app closed would require an ActivityKit push service. Open this page to start again.")).font(.footnote).foregroundStyle(.secondary)
            }
        }.panelScreen().navigationTitle(W("Server Live Activity")).errorAlert($manager.error)
    }
}

