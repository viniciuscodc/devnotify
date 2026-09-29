import AppKit
import SwiftUI
import UserNotifications

@main
enum DevNotifyLauncher {
    static func main() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            FileHandle.standardError.write(Data("DevNotify must run as a macOS app bundle. Use: ./scripts/run-app.sh\n".utf8)); return
        }
        DevNotifyApp.main()
    }
}

struct DevNotifyApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            DevNotifyPopover(calendar: model.calendar, pullRequests: model.pullRequests, settings: model.settings)
        } label: {
            MeetingStatusLabel(store: model.calendar, settings: model.settings)
        }
        .menuBarExtraStyle(.window)
        Settings { PreferencesView(settings: model.settings, calendar: model.calendar) }
    }
}

struct MeetingStatusLabel: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var settings: AppSettings
    private var event: CalendarEvent? { store.current ?? store.next }
    private var color: Color {
        if store.current != nil { return .red }
        guard let event else { return .green }
        return event.startDate.timeIntervalSince(store.now) < 5 * 60 ? .yellow : .green
    }
    var body: some View {
        if settings.menuBarDisplayMode == .icon {
            Image(systemName: "calendar").accessibilityLabel(event.map(label) ?? "No upcoming meetings")
        } else {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(event.map(label) ?? "Free").lineLimit(1)
            }
        }
    }
    private func label(_ event: CalendarEvent) -> String {
        let minutes = max(0, Int(event.startDate.timeIntervalSince(store.now) / 60))
        return "\(store.current != nil ? "In progress" : "In \(minutes)m"): \(String(event.title.prefix(settings.maxTitleLength)))"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let join = UNNotificationAction(identifier: "JOIN", title: "Join", options: [.foreground])
        let openPR = UNNotificationAction(identifier: "OPEN_PR", title: "Open Pull Request", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            .init(identifier: "MEETING_REMINDER", actions: [join], intentIdentifiers: []),
            .init(identifier: "PULL_REQUEST", actions: [openPR], intentIdentifiers: [])
        ])
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestPermission()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        defer { completion() }
        guard let value = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
