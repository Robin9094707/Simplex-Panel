import Foundation

struct WidgetCredential: Codable {
    var provider: String
    var secret: String
}
private final class WidgetRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum WidgetNetwork {
    static func refresh(_ initial: WidgetServer, session suppliedSession: URLSession? = nil, credential suppliedCredential: WidgetCredential? = nil) async -> WidgetServer {
        var record = initial
        guard initial.backgroundRefresh else { return record }
        guard let secret = suppliedCredential?.secret ?? WidgetVault.read(record.id) ?? WidgetVault.read(record.panel), let base = URL(string: record.panel), base.scheme == "https", base.user == nil, base.password == nil else { record.issue = W("Renew widget access in the app"); return record }
        let credential = suppliedCredential ?? (try? JSONDecoder().decode(WidgetCredential.self, from: Data(secret.utf8))) ?? WidgetCredential(provider: "pterodactyl", secret: secret)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12; config.urlCache = nil
        let session = suppliedSession ?? URLSession(configuration: config, delegate: WidgetRedirect(), delegateQueue: nil)
        defer { if suppliedSession == nil { session.invalidateAndCancel() } }
        do {
            var request = URLRequest(url: base.appendingPathComponent("api/client/servers/" + record.serverID + "/resources"))
            request.setValue("Bearer " + credential.secret, forHTTPHeaderField: "Authorization")
            request.setValue("Application/vnd.pterodactyl.v1+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 4 * 1024 * 1024 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(JSON.self, from: data).attributes
            guard !value["current_state"].string.isEmpty else { throw URLError(.cannotParseResponse) }
            let metrics = value["resources"]
            record.state = value["current_state"].string
            record.cpu = PanelNumbers.number(metrics["cpu_absolute"])
            record.memory = PanelNumbers.number(metrics["memory_bytes"])
            record.disk = PanelNumbers.number(metrics["disk_bytes"])
            record.uptime = PanelNumbers.number(metrics["uptime"]).map { $0 / 1000 }
            if record.state == "offline" { record.online = 0; record.playerNames = []; record.playersUpdated = Date(); record.tps = nil; record.uptime = 0 }
            record.updated = Date(); record.issue = nil
            WidgetStorage.cache(record)
        } catch { record.issue = W("Update failed · showing last snapshot") }
        return record
    }
}
