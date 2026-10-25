import SwiftUI

struct MinecraftPropertiesView: View {
    let api: PanelAPI
    let server: Server
    @State private var editor: EditorItem?
    var body: some View {
        List {
            Section {
                Label(W("Minecraft & world"), systemImage: "globe.europe.africa.fill").font(.title2.bold()).foregroundStyle(Color.panelAccent)
                Text(W("Server properties such as difficulty, player limit and world name. Most changes require a restart.")).font(.footnote).foregroundStyle(.secondary)
                Button(W("Open server.properties"), systemImage: "doc.text") { editor = EditorItem(path: "/server.properties") }.requiresAccess(api, server.id, "file.read-content")
                NavigationLink(W("World folders & files")) { FilesView(api: api, server: server, root: "/") }
            }
            Section { Text(W("Switch between text and form in the editor. Comments and unknown properties are preserved.")).foregroundStyle(.secondary) }
        }.panelScreen().navigationTitle(W("Minecraft settings"))
            .sheet(item: $editor) { FileEditor(api: api, server: server, item: $0) {} }
    }
}
