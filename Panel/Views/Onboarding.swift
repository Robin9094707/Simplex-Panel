import SwiftUI

struct WelcomeSetup: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("wing.language") private var language = Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    @AppStorage("wing.onboarded") private var complete = false
    @State private var step = 0
    @State private var connect = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack { Image(systemName: "paperplane.fill").font(.system(size: 52, weight: .light)).foregroundStyle(Color.panelAccent); Spacer(); Text("SIMPLEX").font(.caption.bold()).tracking(4) }
                    Text(step == 0 ? W("Your servers.\nYour Wing.") : W("Your panel.\nConnected directly.")).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Simplex Panel · Community Edition").font(.subheadline).foregroundStyle(.secondary)
                    if step == 0 {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(W("Choose your language")).font(.headline)
                            languageButton("English", code: "en")
                            languageButton("Deutsch", code: "de")
                        }.card()
                        Text(W("Manage servers, open the live console and organize Minecraft plugins and mods directly on your server.")).foregroundStyle(.secondary)
                        Button(W("Continue"), systemImage: "arrow.right") { withAnimation(.snappy) { step = 1 } }.buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("setupNext")
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            Label(W("Pterodactyl & compatible providers"), systemImage: "server.rack")
                            Label(W("Your keys in the iOS keychain"), systemImage: "lock.shield")
                            Label(W("Direct connection without a relay server"), systemImage: "link")
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                        Text(W("Create a Client API key under Account → API Credentials in your panel. You can add multiple panels.")).foregroundStyle(.secondary)
                        Button(W("Connect your first panel"), systemImage: "plus.circle") { connect = true }.buttonStyle(.glassProminent).controlSize(.large)
                        Button(W("Explore the demo first"), systemImage: "sparkles") { store.startDemo(); complete = true }.buttonStyle(.glass).accessibilityIdentifier("setupDemo")
                        Button(W("Set up later")) { complete = true }.foregroundStyle(.secondary)
                    }
                }.padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background { PanelBackground() }.toolbar {
                if step == 1 { ToolbarItem(placement: .topBarLeading) { Button(W("Back"), systemImage: "chevron.left") { step = 0 } } }
            }.sheet(isPresented: $connect, onDismiss: { if !store.profiles.isEmpty { complete = true } }) { AddPanelView() }
        }.environment(\.locale, Locale(identifier: language))
    }
    func languageButton(_ title: String, code: String) -> some View {
        Button { language = code } label: {
            HStack { Text(title); Spacer(); Image(systemName: language == code ? "checkmark.circle.fill" : "circle").foregroundStyle(language == code ? Color.panelAccent : .secondary) }.padding(14)
        }.buttonStyle(.plain).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("language-" + code)
    }
}
