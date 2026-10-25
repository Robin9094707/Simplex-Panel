import SwiftUI
import WidgetKit

@main struct PanelApp: App {
    @UIApplicationDelegateAdaptor(PanelAppDelegate.self) private var appDelegate
    @StateObject private var transfers = TransferManager.shared
    @StateObject private var store = AppStore()
    @StateObject private var workspace = WorkspaceStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme.primary") private var themePrimary = "008F83"
    @AppStorage("theme.secondary") private var themeSecondary = "7046BA"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("wing.language") private var language = Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    @AppStorage("wing.onboarded") private var onboarded = false
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-setup") { UserDefaults.standard.set(false, forKey: "wing.onboarded") }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if store.locked { UnlockView() }
                else { HomeView() }
            }.id(language).onChange(of: language, initial: true) { _, code in if let group = SigningGroups.availableGroup { UserDefaults(suiteName: group)?.set(code, forKey: "wing.language") }; WidgetCenter.shared.reloadAllTimelines() }.environment(\.locale, Locale(identifier: language)).environmentObject(store).environmentObject(workspace).tint(Color.panelAccent)
                .sheet(isPresented: Binding(get: { !onboarded && !ProcessInfo.processInfo.arguments.contains("--demo") }, set: { _ in })) { WelcomeSetup().interactiveDismissDisabled().presentationDetents([.large]).presentationDragIndicator(.visible) }
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onChange(of: store.locked) { _, locked in if !locked && scenePhase == .active { ServerActivityManager.shared.resume(api: store.api, servers: store.servers) } }
                .onChange(of: store.servers) { _, servers in if scenePhase == .active { ServerActivityManager.shared.resume(api: store.api, servers: servers) } }
                .errorAlert($store.error)
                .privacySensitive()
                .overlay { if scenePhase == .background { PanelBackground().overlay { Image(systemName: "server.rack").font(.system(size: 60)).foregroundStyle(.teal) } } }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .background { transfers.persist(force: true); ServerActivityManager.shared.suspend(); store.lock() }
                    if phase == .active { Task { await store.resume(); ServerActivityManager.shared.resume(api: store.api, servers: store.servers) } }
                }
        }
    }
}
struct UnlockView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield").font(.system(size: 64)).foregroundStyle(.teal)
            Text(W("Your panel. Secure.")).font(.largeTitle.bold())
            Button(W("Unlock"), systemImage: "faceid") { Task { await store.unlock() } }.buttonStyle(.glassProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background { PanelBackground() }
    }
}


