import SwiftUI

struct DashboardEditor: View {
    let scope: DashboardScope
    let layoutKey: String
    @ObservedObject private var layouts = DashboardLayouts.shared
    @Environment(\.dismiss) private var dismiss
    @State private var reset = false
    private var cards: [DashboardCard] { layouts.cards(layoutKey, scope: scope) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(scope == .home ? W("Your home screen for this panel. The server list always stays accessible.") : W("Your workspace for this server. Changes are saved automatically.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section(W("Your cards")) {
                    ForEach(cards) { card in
                        HStack {
                            Label(card.title, systemImage: card.symbol)
                            Spacer()
                            if card == .servers { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary).accessibilityLabel(W("Server list stays visible")) }
                            else { Button(W("Hide"), systemImage: "minus.circle", role: .destructive) { layouts.set(cards.filter { $0 != card }, key: layoutKey, scope: scope) }.labelStyle(.iconOnly).buttonStyle(.borderless).accessibilityIdentifier("hide-card-" + card.rawValue) }
                        }
                    }.onMove { source, destination in
                        var next = cards; next.move(fromOffsets: source, toOffset: destination); layouts.set(next, key: layoutKey, scope: scope)
                    }
                }
                Section(W("Add cards")) {
                    ForEach(DashboardCard.available(scope).filter { !cards.contains($0) }) { card in
                        Button { layouts.set(cards + [card], key: layoutKey, scope: scope) } label: { Label(card.title, systemImage: card.symbol) }.accessibilityIdentifier("add-card-" + card.rawValue)
                    }
                    if cards.count == DashboardCard.available(scope).count { Text(W("All cards are visible.")).foregroundStyle(.secondary) }
                }
                Section {
                    Button(W("Restore default layout"), systemImage: "arrow.counterclockwise", role: .destructive) { reset = true }.accessibilityIdentifier("reset-dashboard")
                } footer: { Text(W("Only this layout is reset. Connections, shortcuts, files and other layouts remain.")) }
            }.environment(\.editMode, .constant(.active)).panelScreen().navigationTitle(scope == .home ? W("Customize home") : W("Customize workspace")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { dismiss() }.accessibilityIdentifier("finish-dashboard") } }
                .alert(W("Restore default layout?"), isPresented: $reset) {
                    Button(W("Reset layout"), role: .destructive) { layouts.reset(layoutKey) }.accessibilityIdentifier("confirm-reset-dashboard")
                    Button(W("Cancel"), role: .cancel) {}.accessibilityIdentifier("cancel-reset-dashboard")
                } message: { Text(W("Your arrangement for this overview will be discarded.")) }
        }
    }
}
struct ConsoleHistorySheet: View {
    let historyKey: String
    let choose: (String) -> Void
    @ObservedObject private var history = ConsoleHistory.shared
    @Environment(\.dismiss) private var dismiss
    @State private var clear = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(W("The last 20 successfully sent commands for this server. Tap a command to edit it.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section(W("Recently sent")) {
                    ForEach(Array(history.entries(historyKey).enumerated()), id: \.offset) { _, entry in
                        Button { choose(entry); dismiss() } label: { Text(entry).font(.system(.body, design: .monospaced)).foregroundStyle(.primary) }
                    }
                    if history.entries(historyKey).isEmpty { ContentUnavailableView(W("No command history yet"), systemImage: "clock.arrow.circlepath") }
                }
            }.panelScreen().navigationTitle(W("Command history")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) { Button(W("Clear history"), systemImage: "trash", role: .destructive) { clear = true }.disabled(history.entries(historyKey).isEmpty) }
                }
                .confirmationDialog(W("Clear command history?"), isPresented: $clear, titleVisibility: .visible) { Button(W("Clear history"), role: .destructive) { history.clear(historyKey) } } message: { Text(W("Only this server's local history will be removed.")) }
        }
    }
}
struct ServerIconView: View {
    let api: PanelAPI?
    let server: Server
    var enabled = true
    var revision = 0
    @State private var icon: UIImage?
    var body: some View {
        Group {
            if let icon { Image(uiImage: icon).resizable().interpolation(.none).scaledToFit().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel(W("Server icon")) }
            else { Image(systemName: "cube.transparent.fill").font(.title).foregroundStyle(Color.panelAccent).frame(width: 48, height: 48).accessibilityHidden(true) }
        }.padding(4).background(.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            .task(id: "\(api.map { String(describing: ObjectIdentifier($0)) } ?? "")|\(server.id)|\(enabled)|\(revision)") {
                guard enabled, let api else { icon = nil; return }
                let data = await api.serverIcons.load(api: api, server: server, force: revision > 0)
                guard !Task.isCancelled else { return }; icon = data.flatMap { UIImage(data: $0) }
            }
    }
}

