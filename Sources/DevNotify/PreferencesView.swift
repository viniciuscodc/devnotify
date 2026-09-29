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
        .padding(16).frame(width: 620, height: 650)
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
            Section("Google Calendar setup") {
                InfoCallout(
                    symbol: "calendar.badge.exclamationmark",
                    title: "Connect Google Calendar to Apple Calendar",
                    message: "DevNotify reads events from the macOS Calendar database. If your meetings are in Google Calendar, open Apple Calendar, choose Calendar → Add Account, select Google, sign in, and make sure Calendars is enabled."
                )
                Text("After connecting the account, confirm your Google calendars are visible in Apple Calendar. DevNotify cannot read meetings directly from the Google Calendar website.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                InfoCallout(
                    symbol: "key.fill",
                    title: "A token is required",
                    message: "The Pull Requests tab cannot load GitHub data until you add a personal access token. DevNotify uses it to read PRs, reviews, CI checks and workflow runs, and—when you choose those actions—to merge a PR or re-run failed jobs."
                )
                VStack(alignment: .leading, spacing: 7) {
                    Text("Personal access token").font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        ZStack {
                            SecureField("github_pat_…", text: $settings.token)
                                .opacity(showsToken ? 0 : 1)
                                .allowsHitTesting(!showsToken)
                            TextField("github_pat_…", text: $settings.token)
                                .opacity(showsToken ? 1 : 0)
                                .allowsHitTesting(showsToken)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, minHeight: 24)

                        Button { showsToken.toggle() } label: {
                            Label(showsToken ? "Hide" : "Show", systemImage: showsToken ? "eye.slash" : "eye")
                                .frame(width: 56)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                HStack {
                    Label(settings.token.isEmpty ? "Token not configured" : "Stored securely in your macOS login Keychain",
                          systemImage: settings.token.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .foregroundStyle(settings.token.isEmpty ? .orange : .green)
                    Spacer()
                    Link("Create token…", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                }.font(.caption)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fine-grained repository permissions:").fontWeight(.medium)
                    Text("Metadata: Read (automatic) · Pull requests: Read · Checks: Read · Commit statuses: Read · Contents: Write (merge) · Actions: Write (re-run failed jobs)")
                    Text("Select every repository DevNotify should monitor. Your organization may need to approve the token.")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Section("Repositories and organizations") {
                SettingsTextEditor(
                    title: "Repositories or organization names",
                    example: "Example: acme/ios-app, acme/api, my-organization",
                    text: $settings.targets,
                    detail: "Separate entries with commas or new lines. Leave empty to find PRs you authored, are assigned to, or were asked to review."
                )
            }
            Section("Filter by authors") {
                SettingsTextEditor(
                    title: "GitHub usernames",
                    example: "Example: alice, bob, octocat",
                    text: $settings.filteredUsers,
                    detail: "Optional. Only PRs authored by these users will be shown. Commas, spaces, and new lines are accepted; @ is optional."
                )
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

private struct InfoCallout: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.blue).font(.title3).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsTextEditor: View {
    let title: String
    let example: String
    @Binding var text: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.medium))
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(example).foregroundStyle(.tertiary).padding(.horizontal, 7).padding(.vertical, 7)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(3)
            }
            .frame(height: 58)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
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
