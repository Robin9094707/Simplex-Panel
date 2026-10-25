import SwiftUI
import CoreImage.CIFilterBuiltins

struct AccountView: View {
    let api: PanelAPI
    @State private var account: JSON = .null
    @State private var operation: Operation?
    @State private var error: String?
    var body: some View {
        List {
            Section("Account") {
                LabeledContent(W("Username"), value: account["username"].string)
                LabeledContent("E-Mail", value: account["email"].string)
                LabeledContent(W("Language"), value: account["language"].string)
            }
            Section(W("Security")) {
                Button(W("Change email"), systemImage: "envelope") { operation = Operation(title: W("Change email"), path: "account/email", method: "PUT", fields: [Field(key: "email", label: W("New email"), value: account["email"].string), Field(key: "password", label: W("Account password"), kind: .secret)]) }.requiresRequest(api, "account/email", method: "PUT")
                Button(W("Change password"), systemImage: "key") { operation = Operation(title: W("Change password"), path: "account/password", method: "PUT", fields: [Field(key: "current_password", label: W("Current password"), kind: .secret), Field(key: "password", label: W("New password"), kind: .secret), Field(key: "password_confirmation", label: W("Repeat new password"), kind: .secret)], destructive: true) }.requiresRequest(api, "account/password", method: "PUT")
                NavigationLink { TwoFactorView(api: api) } label: { Label(W("Two-factor authentication"), systemImage: "lock.shield") }
                NavigationLink { AccountKeysView(api: api, ssh: false) } label: { Label(W("API keys"), systemImage: "key.horizontal") }
                NavigationLink { AccountKeysView(api: api, ssh: true) } label: { Label(W("SSH keys"), systemImage: "terminal") }
                NavigationLink { ActivityView(api: api, path: "account/activity") } label: { Label(W("Account activity"), systemImage: "clock.arrow.circlepath") }
            }
        }.panelScreen().navigationTitle("Account").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }.errorAlert($error)
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
    }
    func load() async { do { account = try await api.request("account").attributes } catch { self.error = error.localizedDescription } }
}
struct AccountKeysView: View {
    let api: PanelAPI
    let ssh: Bool
    @State private var rows: [JSON] = []
    @State private var operation: Operation?
    @State private var create = false
    @State private var result: DetailItem?
    @State private var error: String?
    var path: String { ssh ? "account/ssh-keys" : "account/api-keys" }
    var body: some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row[ssh ? "name" : "description"].string).font(.headline)
                    Text(row[ssh ? "fingerprint" : "identifier"].string).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Button(W("Remove"), systemImage: "trash", role: .destructive) {
                        operation = Operation(title: W("Remove key"), detail: W("Applications using this key will lose access."), path: ssh ? path + "/remove" : path + "/" + row["identifier"].string, method: ssh ? "POST" : "DELETE", fixed: ssh ? ["fingerprint": row["fingerprint"]] : [:], destructive: true, submit: W("Remove"))
                    }
                }.padding(.vertical, 5)
            }
            if rows.isEmpty { ContentUnavailableView(W("No keys"), systemImage: "key") }
        }.panelScreen().navigationTitle(ssh ? W("SSH keys") : W("API keys")).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }.errorAlert($error)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(W("Create key"), systemImage: "plus") { create = true } } }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
            .sheet(isPresented: $create) {
                ActionForm(title: ssh ? W("Add SSH key") : W("Create Client key"), fields: ssh ? [Field(key: "name", label: W("Name")), Field(key: "public_key", label: W("Public SSH key"), kind: .multiline, hint: W("Paste only the public key, never a private key."))] : [Field(key: "description", label: W("Description")), Field(key: "allowed_ips", label: W("Allowed IP addresses"), kind: .strings, hint: W("Optional. One address per line; empty allows all addresses."))], submit: W("Create")) { values in
                    guard !api.demo else { throw PanelError(message: W("Not available in demo mode.")) }
                    let response = try await api.request(path, method: "POST", body: .object(values))
                    await load()
                    // Present only after the creation sheet has closed.
                    if !ssh { Task { try? await Task.sleep(for: .milliseconds(500)); result = DetailItem(data: response) } }
                }
            }
            .sheet(item: $result) { item in NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Label(W("Store this key securely now"), systemImage: "key.fill").font(.headline)
                    Text(W("The panel shows the complete key only when creating it. It is included in the response below.")).foregroundStyle(.secondary)
                    ScrollView { Text(item.data.pretty).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                }.padding().panelScreen().navigationTitle(W("New API key")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(W("Done")) { result = nil } } }.privacySensitive()
            } }
    }
    func load() async { do { rows = try await api.list(path) } catch { self.error = error.localizedDescription } }
}
struct TwoFactorView: View {
    let api: PanelAPI
    @State private var setup: JSON = .null
    @State private var error: String?
    @State private var enable = false
    @State private var operation: Operation?
    @State private var tokens: [String] = []
    var body: some View {
        List {
            Section {
                Text(W("Secure your panel account with an authenticator app.")).foregroundStyle(.secondary)
                Button(W("Load setup"), systemImage: "qrcode") { Task { do { setup = try await api.request("account/two-factor")["data"] } catch { self.error = error.localizedDescription } } }
            } footer: { Text(W("If 2FA is already enabled, the panel reports this when loading setup.")) }
            if setup != .null {
                Section(W("Set up authenticator")) {
                    if let image = qrImage(setup["image_url_data"].string.isEmpty ? setup["image_url"].string : setup["image_url_data"].string) { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 220).padding().background(.white, in: RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity) }
                    Text(setup["secret"].string).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text(W("Add the key to your authenticator app and confirm with the six-digit code.")).font(.caption).foregroundStyle(.secondary)
                    Button(W("Confirm activation"), systemImage: "checkmark.shield") { enable = true }
                }
            }
            if !tokens.isEmpty {
                Section(W("Recovery codes · store securely")) {
                    ForEach(tokens, id: \.self) { Text($0).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    Text(W("These codes are only shown now. Store them securely outside this device.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(W("Disable 2FA"), systemImage: "lock.open", role: .destructive) { operation = Operation(title: W("Disable 2FA"), detail: W("The additional sign-in protection on your panel account will be removed."), path: "account/two-factor/disable", fields: [Field(key: "password", label: W("Account password"), kind: .secret)], destructive: true, submit: W("Disable")) }.requiresRequest(api, "account/two-factor/disable", method: "POST")
            }
        }.panelScreen().navigationTitle(W("Two-factor protection")).navigationBarTitleDisplayMode(.inline).errorAlert($error).privacySensitive()
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { setup = .null; tokens = [] } }
            .sheet(isPresented: $enable) {
                ActionForm(title: W("Enable 2FA"), fields: [Field(key: "code", label: W("Six-digit code")), Field(key: "password", label: W("Account password"), kind: .secret)], submit: W("Enable")) { values in
                    guard !api.demo else { throw PanelError(message: W("Not available in demo mode.")) }
                    let response = try await api.request("account/two-factor", method: "POST", body: .object(values))
                    tokens = response.attributes["tokens"].array.map(\.string); setup = .null
                }
            }
    }
    func qrImage(_ text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

