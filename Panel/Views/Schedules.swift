import SwiftUI

func scheduleFields(_ s: JSON = .null) -> [Field] {
    [Field(key: "name", label: W("Name"), value: s["name"].string),
     Field(key: "minute", label: W("Minute"), value: s["cron"]["minute"].string.isEmpty ? "0" : s["cron"]["minute"].string, hint: W("0–59, * or e.g. */15")),
     Field(key: "hour", label: W("Hour"), value: s["cron"]["hour"].string.isEmpty ? "4" : s["cron"]["hour"].string, hint: W("0–23. Uses the panel's time zone.")),
     Field(key: "day_of_month", label: W("Day of month"), value: s["cron"]["day_of_month"].string.isEmpty ? "*" : s["cron"]["day_of_month"].string),
     Field(key: "month", label: W("Month"), value: s["cron"]["month"].string.isEmpty ? "*" : s["cron"]["month"].string),
     Field(key: "day_of_week", label: W("Day of week"), value: s["cron"]["day_of_week"].string.isEmpty ? "*" : s["cron"]["day_of_week"].string, hint: W("0 = Sunday, 1 = Monday, …, 6 = Saturday")),
     Field(key: "is_active", label: W("Enabled"), value: s == .null || s["is_active"].bool ? "true" : "false", kind: .toggle),
     Field(key: "only_when_online", label: W("Only while the server is running"), value: s["only_when_online"].bool ? "true" : "false", kind: .toggle)]
}
struct SchedulesView: View {
    let api: PanelAPI
    let server: Server
    @State private var schedules: [JSON] = []
    @State private var editing = false
    @State private var error: String?
    @State private var operation: Operation?
    var prefix: String { "servers/\(server.id)/schedules" }
    var body: some View {
        List {
            PanelTimeView(api: api)
            if schedules.isEmpty { ContentUnavailableView(W("No schedules"), systemImage: "calendar.badge.clock", description: Text(W("Schedule commands, power actions and backups."))) }
            ForEach(schedules, id: \.["id"].string) { schedule in
                NavigationLink { ScheduleDetail(api: api, prefix: prefix, initial: schedule) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Color.panelAccent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(schedule["name"].string).font(.headline)
                            Text(ScheduleTime.display(schedule["next_run_at"].string)).font(.caption).foregroundStyle(.secondary)
                            Text(schedule["is_active"].bool ? W("Enabled") : W("Paused")).font(.caption).foregroundStyle(schedule["is_active"].bool ? Color.green : Color.secondary)
                        }
                    }.padding(.vertical, 5)
                }
            }
        }.panelScreen().navigationTitle(W("Schedules")).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(W("New schedule"), systemImage: "plus") { editing = true }.requiresRequest(api, prefix, method: "POST") } }
            .sheet(item: $operation) { OperationSheet(api: api, operation: $0) { await load() } }
            .sheet(isPresented: $editing) { ScheduleEditor(api: api, path: prefix) { await load() } }.errorAlert($error)
    }
    func load() async { do { schedules = try await api.list(prefix) } catch { self.error = error.localizedDescription } }
}
struct ScheduleDetail: View {
    let api: PanelAPI
    let prefix: String
    let initial: JSON
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: JSON = .null
    @State private var editing = false
    @State private var taskEditing: EditorItem?
    @State private var taskInitial: JSON = .null
    @State private var operation: Operation?
    @State private var error: String?
    var data: JSON { schedule == .null ? initial : schedule }
    var path: String { prefix + "/" + initial["id"].string }
    var tasks: [JSON] { data["relationships"]["tasks"].rows }
    var body: some View {
        List {
            PanelTimeView(api: api)
            Section(W("Schedule")) {
                LabeledContent("Status", value: data["is_processing"].bool ? W("Running") : data["is_active"].bool ? W("Enabled") : W("Paused"))
                LabeledContent(W("Next run"), value: ScheduleTime.display(data["next_run_at"].string))
                LabeledContent(W("Last run"), value: ScheduleTime.display(data["last_run_at"].string))
                Text(["minute", "hour", "day_of_month", "month", "day_of_week"].map { data["cron"][$0].string.isEmpty ? "*" : data["cron"][$0].string }.joined(separator: " ")).font(.system(.body, design: .monospaced))
                Button(W("Edit schedule"), systemImage: "pencil") { editing = true }.requiresRequest(api, path, method: "POST")
                Button(W("Run now"), systemImage: "play") { operation = Operation(title: W("Run schedule"), detail: W("All tasks in this schedule will run."), path: path + "/execute", submit: W("Run")) }.requiresRequest(api, path + "/execute", method: "POST")
            }
            Section(W("Tasks · \(tasks.count)")) {
                ForEach(tasks, id: \.["id"].string) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("\(task["sequence_id"].string). " + (["command": W("Console command"), "power": W("Power action"), "backup": "Backup"][task["action"].string] ?? task["action"].string)).font(.headline); Spacer(); Menu {
                            Button(W("Edit"), systemImage: "pencil") { taskForm(task) }.requiresRequest(api, path + "/tasks")
                            Button(W("Delete"), systemImage: "trash", role: .destructive) { operation = Operation(title: W("Delete task"), path: path + "/tasks/\(task["id"].string)", method: "DELETE", destructive: true, submit: W("Delete")) }.requiresRequest(api, path + "/tasks/\(task["id"].string)", method: "DELETE")
                        } label: { Image(systemName: "ellipsis.circle").padding(6) } }
                        Text(task["payload"].string.isEmpty ? W("No payload") : task["payload"].string).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        Text(W("Delay: \(task["time_offset"].string) s")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                Button(W("Add task"), systemImage: "plus") { taskForm(.null) }.requiresRequest(api, path + "/tasks")
            }
            Section { Button(W("Delete schedule"), systemImage: "trash", role: .destructive) { operation = Operation(title: W("Delete schedule"), detail: W("All related tasks will also be removed."), path: path, method: "DELETE", destructive: true, submit: W("Delete")) } }.requiresRequest(api, path, method: "DELETE")
        }.panelScreen().navigationTitle(data["name"].string).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }.errorAlert($error)
            .sheet(isPresented: $editing) { ScheduleEditor(api: api, path: path, initial: data) { await load() } }
            .sheet(item: $taskEditing) { item in ScheduleTaskEditor(api: api, path: item.path, initial: taskInitial, count: tasks.count) { await load() } }
            .sheet(item: $operation) { op in OperationSheet(api: api, operation: op) { if op.method == "DELETE" && op.path == path { dismiss() } else { await load() } } }
    }
    func load() async { guard !api.demo else { return }; do { schedule = try await api.request(path).attributes } catch { self.error = error.localizedDescription } }
    func taskForm(_ task: JSON) {
        taskInitial = task
        taskEditing = EditorItem(path: path + "/tasks" + (task == .null ? "" : "/\(task["id"].string)"))
    }
}

