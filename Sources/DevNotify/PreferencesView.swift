import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var calendar: CalendarStore
    @StateObject private var permissions = PermissionStatus()
    @State private var showsToken = false

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gear") }
            meetings.tabItem { Label("Meetings", systemImage: "calendar") }
            github.tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .padding(16).frame(width: 590, height: 600)
        .task { await permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await permissions.refresh() } }
    }

    private var general: some View {
        Form {
            Section("Startup") {
                Toggle("Open DevNotify at login", isOn: $settings.openAtLogin)
                Text("Enabled by default. macOS may ask you to confirm this in Login Items.").font(.caption).foregroundStyle(.secondary)
                if let error = settings.loginItemError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section("Notifications") {
                Toggle("Mute all notifications", isOn: $settings.notificationsMuted)
                Toggle("Notify when someone reviews my pull request", isOn: $settings.reviewNotificationsEnabled)
                    .disabled(settings.notificationsMuted)
                HStack {
                    Text("System permission"); Text(permissions.notificationStatusText).foregroundStyle(permissions.notificationsAreAllowed ? .green : .red)
                    Spacer()
                    Button(permissions.notificationAuthorization == .notDetermined ? "Allow Notifications" : "Open Settings") {
                        if permissions.notificationAuthorization == .notDetermined { Task { await permissions.requestNotificationAccess() } }
                        else { permissions.openNotificationSettings() }
                    }
                    Button("Send Test") { Task { await permissions.sendTestNotification() } }
                }
                if let error = permissions.testNotificationError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section("Window") {
                Picker("Popover height", selection: $settings.popoverHeight) {
                    Text("Compact — 480 pt").tag(480); Text("Standard — 620 pt").tag(620)
                    Text("Tall — 720 pt").tag(720); Text("Extra Tall — 800 pt").tag(800)
                }
            }
        }.formStyle(.grouped)
    }

    private var meetings: some View {
        Form {
            Section("Calendar permission") {
                HStack {
                    Text("Calendar"); Text(permissions.calendarStatusText).foregroundStyle(permissions.calendarIsAllowed ? .green : .red)
                    Spacer(); Button("Open Calendar Settings", action: permissions.openCalendarSettings)
                }
                Text("DevNotify needs calendar access to display meetings and call links.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Reminders") {
                Picker("Remind me before a meeting", selection: $settings.reminderMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0) }
                }
            }
            Section("Menu bar") {
                Picker("Show", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Title length: \(settings.maxTitleLength)", value: $settings.maxTitleLength, in: 12...60)
                    .disabled(settings.menuBarDisplayMode == .icon)
            }
        }.formStyle(.grouped)
    }

    private var github: some View {
        Form {
            Section("GitHub connection") {
                HStack {
                    Group {
                        if showsToken { TextField("github_pat_… or ghp_…", text: $settings.token) }
                        else { SecureField("github_pat_… or ghp_…", text: $settings.token) }
                    }.textFieldStyle(.roundedBorder).font(.body.monospaced())
                    Button { showsToken.toggle() } label: { Image(systemName: showsToken ? "eye.slash" : "eye") }.buttonStyle(.bordered)
                }
                Text("The token is stored in your macOS login Keychain.").font(.caption).foregroundStyle(.secondary)
                Link("Create a fine-grained token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
            }
            Section("Repositories and organizations") {
                TextField("acme/ios-app, acme/api, my-organization", text: $settings.targets, axis: .vertical).lineLimit(3...5)
                Text("Separate entries with commas or new lines. Leave empty to use PRs you authored, are assigned to, or were asked to review.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Filter by authors") {
                TextField("alice, bob, octocat", text: $settings.filteredUsers, axis: .vertical).lineLimit(2...4)
            }
            Section("Updates") {
                Picker("Refresh every", selection: $settings.pollMinutes) {
                    ForEach([2, 3, 5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Global shortcuts") {
                ShortcutRow(title: "Join current or next meeting", enabled: $settings.meetingShortcutEnabled, key: $settings.meetingShortcutKey)
                ShortcutRow(title: "Open first Ready to Merge PR", enabled: $settings.readyHotKeyEnabled, key: $settings.readyHotKey)
                ShortcutRow(title: "Open first Review List PR", enabled: $settings.reviewHotKeyEnabled, key: $settings.reviewHotKey)
                Text("All shortcuts use Command–Shift plus the selected key. Choose a different key for each enabled action.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let title: String; @Binding var enabled: Bool; @Binding var key: String
    var body: some View {
        HStack { Toggle(title, isOn: $enabled); Spacer(); Text("⌘⇧"); Picker("Key", selection: $key) {
            ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) }
        }.labelsHidden().frame(width: 65).disabled(!enabled) }
    }
}
