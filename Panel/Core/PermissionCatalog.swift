import Foundation
import Combine

struct PermissionChoice: Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
}
struct PermissionGroup: Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var choices: [PermissionChoice]
}
enum PermissionCatalog {
    static var groupNames: [String: String] { ["websocket": W("Live connection"), "control": W("Console & power controls"), "user": W("Subusers"), "file": W("Files & SFTP"), "backup": "Backups", "allocation": W("Network & ports"), "startup": W("Startup parameters"), "database": W("Databases"), "schedule": W("Schedules"), "settings": W("Server settings"), "activity": W("Activity")] }
    static var actionNames: [String: String] { ["read": W("View"), "create": W("Create"), "update": W("Edit"), "delete": W("Delete"), "download": W("Download"), "restore": W("Restore"), "start": W("Start"), "stop": W("Stop"), "restart": W("Restart"), "console": W("Send commands"), "connect": W("Connect live console"), "read-content": W("Read & download file contents"), "view_password": W("View password"), "archive": W("Compress & extract"), "sftp": W("Use SFTP"), "docker-image": W("Change Docker image"), "rename": W("Change name & description"), "reinstall": W("Reinstall")] }
    static func decode(_ response: JSON) -> [PermissionGroup] {
        var source = response.attributes
        if source["data"] != .null { source = source["data"].attributes }
        if source["permissions"] != .null { source = source["permissions"] }
        var groups: [String: PermissionGroup] = [:]
        func add(_ id: String, value: JSON, groupID: String, group: JSON = .null) {
            guard id.range(of: #"^[A-Za-z0-9_.:*-]+$"#, options: .regularExpression) != nil else { return }
            let title = value["name"].string.isEmpty ? value["label"].string : value["name"].string
            let description = value["description"].string.isEmpty ? value.string : value["description"].string
            var row = groups[groupID] ?? PermissionGroup(id: groupID, title: group["name"].string.isEmpty ? (groupNames[groupID] ?? groupID.replacingOccurrences(of: "_", with: " ").capitalized) : group["name"].string, description: group["description"].string, choices: [])
            let action = String(id.split(separator: ".").last ?? "")
            if !row.choices.contains(where: { $0.id == id }) { row.choices.append(PermissionChoice(id: id, title: title.isEmpty ? (actionNames[action] ?? action.replacingOccurrences(of: "_", with: " ").capitalized) : title, description: description)) }
            groups[groupID] = row
        }
        if case .array(let values) = source {
            for item in values {
                let row = item.attributes
                let id = row["permission"].string.isEmpty ? (row["id"].string.isEmpty ? row.string : row["id"].string) : row["permission"].string
                if !id.isEmpty { add(id, value: row, groupID: row["group"].string.isEmpty ? String(id.split(separator: ".").first ?? "other") : row["group"].string) }
            }
        } else {
            for (groupID, group) in source.object.sorted(by: { $0.key < $1.key }) {
                if groupID.contains(".") { add(groupID, value: group, groupID: String(groupID.split(separator: ".")[0])); continue }
                let keys = group["keys"] == .null ? group["permissions"] : group["keys"]
                if case .object(let values) = keys {
                    for (key, value) in values.sorted(by: { $0.key < $1.key }) { add(key.contains(".") ? key : groupID + "." + key, value: value, groupID: groupID, group: group) }
                } else {
                    for item in keys.array {
                        let key = item["permission"].string.isEmpty ? (item["id"].string.isEmpty ? item.string : item["id"].string) : item["permission"].string
                        if !key.isEmpty { add(key.contains(".") ? key : groupID + "." + key, value: item, groupID: groupID, group: group) }
                    }
                }
            }
        }
        return groups.values.map { group in var row = group; row.choices.sort { $0.id < $1.id }; return row }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
@MainActor final class PermissionCatalogStore: ObservableObject {
    @Published var groups: [PermissionGroup] = []
    @Published var loading = false
    @Published var issue: String?
    func load(_ api: PanelAPI) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let response = try await api.request("permissions")
            let decoded = PermissionCatalog.decode(response)
            guard !decoded.isEmpty else { throw PanelError(message: W("The panel did not provide a readable permission catalog.")) }
            groups = decoded; issue = nil
        } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
}

