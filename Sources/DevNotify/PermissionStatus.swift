import AppKit
import EventKit
import UserNotifications

@MainActor
final class PermissionStatus: ObservableObject {
    @Published private(set) var calendarAuthorization = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationAlerts: UNNotificationSetting = .notSupported
    @Published private(set) var testNotificationError: String?

    var calendarIsAllowed: Bool { calendarAuthorization == .fullAccess }
    var calendarStatusText: String {
        switch calendarAuthorization {
        case .authorized, .fullAccess: "Allowed"; case .notDetermined: "Not requested"; case .denied: "Denied"
        case .restricted: "Restricted"; case .writeOnly: "Write only"; @unknown default: "Unknown"
        }
    }
    var notificationsAreAllowed: Bool {
        (notificationAuthorization == .authorized || notificationAuthorization == .provisional) && notificationAlerts == .enabled
    }
    var notificationStatusText: String {
        switch notificationAuthorization {
        case .notDetermined: "Not requested"; case .denied: "Denied"
        case .authorized, .provisional: notificationAlerts == .enabled ? "Allowed" : "Alerts off"
        case .ephemeral: "Temporary"; @unknown default: "Unknown"
        }
    }

    func refresh() async {
        calendarAuthorization = EKEventStore.authorizationStatus(for: .event)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = settings.authorizationStatus; notificationAlerts = settings.alertSetting
    }
    func requestNotificationAccess() async {
        testNotificationError = nil
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { testNotificationError = error.localizedDescription }
        await refresh()
    }
    func sendTestNotification() async {
        if notificationAuthorization == .notDetermined { await requestNotificationAccess() }
        guard notificationAuthorization == .authorized || notificationAuthorization == .provisional else {
            testNotificationError = "Notifications are not allowed for DevNotify."; return
        }
        let content = UNMutableNotificationContent(); content.title = "DevNotify test"; content.body = "Notifications are configured correctly."; content.sound = .default
        do { try await UNUserNotificationCenter.current().add(.init(identifier: "devnotify-test", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) }
        catch { testNotificationError = error.localizedDescription }
    }
    func openCalendarSettings() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") }
    func openNotificationSettings() { open("x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
    private func open(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }
}
