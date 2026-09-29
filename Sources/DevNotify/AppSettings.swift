import Foundation
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case meetingTitle
    case icon

    var id: Self { self }
    var label: String { self == .meetingTitle ? "Meeting title" : "Icon only" }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let reminderMinutes = "reminderMinutes"
        static let notificationsMuted = "notificationsMuted"
        static let reviewNotificationsEnabled = "reviewNotificationsEnabled"
        static let openAtLogin = "openAtLogin"
        static let autoUpdatesEnabled = "autoUpdatesEnabled"
        static let meetingShortcutEnabled = "meetingShortcutEnabled"
        static let meetingShortcutKey = "meetingShortcutKey"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let maxTitleLength = "maxTitleLength"
        static let targets = "githubTargets"
        static let pollMinutes = "pollMinutes"
        static let filteredUsers = "filteredUsers"
        static let popoverHeight = "popoverHeight"
        static let readyHotKeyEnabled = "readyHotKeyEnabled"
        static let readyHotKey = "readyHotKey"
        static let reviewHotKeyEnabled = "reviewHotKeyEnabled"
        static let reviewHotKey = "reviewHotKey"
    }

    var onChange: (() -> Void)?
    var onCredentialsChange: (() -> Void)?

    @Published var reminderMinutes: Int { didSet { save(reminderMinutes, Key.reminderMinutes) } }
    @Published var notificationsMuted: Bool { didSet { save(notificationsMuted, Key.notificationsMuted) } }
    @Published var reviewNotificationsEnabled: Bool { didSet { save(reviewNotificationsEnabled, Key.reviewNotificationsEnabled) } }
    @Published var openAtLogin: Bool {
        didSet {
            save(openAtLogin, Key.openAtLogin)
            configureOpenAtLogin()
        }
    }
    @Published var autoUpdatesEnabled: Bool { didSet { save(autoUpdatesEnabled, Key.autoUpdatesEnabled) } }
    @Published var meetingShortcutEnabled: Bool { didSet { save(meetingShortcutEnabled, Key.meetingShortcutEnabled) } }
    @Published var meetingShortcutKey: String { didSet { save(meetingShortcutKey, Key.meetingShortcutKey) } }
    @Published var menuBarDisplayMode: MenuBarDisplayMode { didSet { save(menuBarDisplayMode.rawValue, Key.menuBarDisplayMode) } }
    @Published var maxTitleLength: Int { didSet { save(maxTitleLength, Key.maxTitleLength) } }
    @Published var token: String { didSet { KeychainStore.saveToken(token); onCredentialsChange?() } }
    @Published var targets: String { didSet { save(targets, Key.targets); onCredentialsChange?() } }
    @Published var pollMinutes: Int { didSet { save(pollMinutes, Key.pollMinutes) } }
    @Published var filteredUsers: String { didSet { save(filteredUsers, Key.filteredUsers) } }
    @Published var popoverHeight: Int { didSet { save(popoverHeight, Key.popoverHeight) } }
    @Published var readyHotKeyEnabled: Bool { didSet { save(readyHotKeyEnabled, Key.readyHotKeyEnabled) } }
    @Published var readyHotKey: String { didSet { save(readyHotKey, Key.readyHotKey) } }
    @Published var reviewHotKeyEnabled: Bool { didSet { save(reviewHotKeyEnabled, Key.reviewHotKeyEnabled) } }
    @Published var reviewHotKey: String { didSet { save(reviewHotKey, Key.reviewHotKey) } }
    @Published private(set) var loginItemError: String?

    init(defaults: UserDefaults = .standard) {
        reminderMinutes = defaults.object(forKey: Key.reminderMinutes) as? Int ?? 5
        notificationsMuted = defaults.object(forKey: Key.notificationsMuted) as? Bool ?? false
        reviewNotificationsEnabled = defaults.object(forKey: Key.reviewNotificationsEnabled) as? Bool ?? true
        openAtLogin = defaults.object(forKey: Key.openAtLogin) as? Bool ?? true
        autoUpdatesEnabled = defaults.object(forKey: Key.autoUpdatesEnabled) as? Bool ?? true
        meetingShortcutEnabled = defaults.object(forKey: Key.meetingShortcutEnabled) as? Bool ?? true
        meetingShortcutKey = defaults.string(forKey: Key.meetingShortcutKey) ?? "J"
        menuBarDisplayMode = defaults.string(forKey: Key.menuBarDisplayMode).flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .meetingTitle
        maxTitleLength = defaults.object(forKey: Key.maxTitleLength) as? Int ?? 28
        token = KeychainStore.loadToken()
        targets = defaults.string(forKey: Key.targets) ?? ""
        pollMinutes = defaults.object(forKey: Key.pollMinutes) as? Int ?? 3
        filteredUsers = defaults.string(forKey: Key.filteredUsers) ?? ""
        popoverHeight = defaults.object(forKey: Key.popoverHeight) as? Int ?? 620
        readyHotKeyEnabled = defaults.object(forKey: Key.readyHotKeyEnabled) as? Bool ?? true
        readyHotKey = defaults.string(forKey: Key.readyHotKey) ?? "M"
        reviewHotKeyEnabled = defaults.object(forKey: Key.reviewHotKeyEnabled) as? Bool ?? true
        reviewHotKey = defaults.string(forKey: Key.reviewHotKey) ?? "R"
        if openAtLogin { configureOpenAtLogin() }
    }

    var parsedTargets: [String] {
        targets.components(separatedBy: CharacterSet(charactersIn: ",\n ")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var parsedFilteredUsers: Set<String> {
        Set(filteredUsers.components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty })
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }

    private func configureOpenAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if openAtLogin {
                if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
    }
}
