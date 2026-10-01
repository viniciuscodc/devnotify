import AppKit
import Foundation
import OSLog
import UserNotifications

enum NotificationService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DevNotify", category: "Notifications")
    @MainActor private static var meetingTask: Task<Void, Never>?
    @MainActor private static var scheduledDates: [String: Date] = [:]

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func scheduleMeetings(_ events: [CalendarEvent], minutesBefore: Int, muted: Bool, requestAuthorization: Bool = false) {
        let previous = meetingTask
        meetingTask = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            var authorization = await center.notificationSettings().authorizationStatus
            if authorization == .notDetermined && requestAuthorization {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                authorization = await center.notificationSettings().authorizationStatus
            }
            guard authorization == .authorized || authorization == .provisional else { return }
            let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("meeting-reminder-") }
            if muted {
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier)); scheduledDates.removeAll(); return
            }
            let now = Date()
            let desired = Set(events.map { "meeting-reminder-\($0.id)" })
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !desired.contains($0) })
            scheduledDates = scheduledDates.filter { desired.contains($0.key) }
            for event in events where event.startDate > now {
                let identifier = "meeting-reminder-\(event.id)"
                let intended = event.startDate.addingTimeInterval(-Double(minutesBefore * 60))
                if intended <= now && scheduledDates[identifier] == intended { continue }
                let date = max(intended, now.addingTimeInterval(1))
                let content = UNMutableNotificationContent(); content.title = event.title
                content.body = intended > now ? "Starts in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")" : "Starts at \(event.startDate.formatted(date: .omitted, time: .shortened))"
                content.sound = .default
                let meetingSymbol = event.videoURL != nil ? "video.circle.fill" : "calendar"
                if let icon = iconAttachment(symbolName: meetingSymbol, color: .systemBlue) { content.attachments = [icon] }
                if let url = event.videoURL { content.categoryIdentifier = "MEETING_REMINDER"; content.userInfo = ["url": url.absoluteString] }
                let components = Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: date)
                do {
                    try await center.add(.init(identifier: identifier, content: content,
                                               trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                    scheduledDates[identifier] = intended
                } catch { logger.error("Meeting notification failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    static func ready(_ pullRequest: PullRequest) {
        send(title: "PR Ready to Merge", body: pullRequest.title, pullRequest: pullRequest,
             icon: iconAttachment(symbolName: "checkmark.circle.fill", color: .systemGreen))
    }

    static func reviewed(_ pullRequest: PullRequest, review: PullRequestReview) {
        let action: String
        let icon: UNNotificationAttachment?
        switch review.state {
        case "APPROVED":
            action = "approved"
            icon = iconAttachment(symbolName: "hand.thumbsup.fill", color: .systemGreen)
        case "CHANGES_REQUESTED":
            action = "requested changes on"
            icon = iconAttachment(symbolName: "pencil.circle.fill", color: .systemOrange)
        default:
            action = "reviewed"
            icon = iconAttachment(symbolName: "text.bubble.fill", color: .systemGray)
        }
        send(title: "PR Reviewed", body: "@\(review.reviewer) \(action) \(pullRequest.repository) #\(pullRequest.number): \(pullRequest.title)",
             pullRequest: pullRequest, icon: icon)
    }

    private static func send(title: String, body: String, pullRequest: PullRequest, icon: UNNotificationAttachment?) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        content.categoryIdentifier = "PULL_REQUEST"; content.userInfo = ["url": pullRequest.url.absoluteString]
        if let icon { content.attachments = [icon] }
        UNUserNotificationCenter.current().add(.init(identifier: "pr-\(pullRequest.id)-\(UUID())", content: content, trigger: nil))
    }

    private static func iconAttachment(symbolName: String, color: NSColor) -> UNNotificationAttachment? {
        let size = CGFloat(128)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: bounds.insetBy(dx: 4, dy: 4))
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
            guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return false }
            let symbolRect = bounds.insetBy(dx: size * 0.22, dy: size * 0.22)
            let tinted = NSImage(size: symbolRect.size, flipped: false) { r in
                symbol.draw(in: r)
                NSColor.white.setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dn_\(symbolName.replacingOccurrences(of: ".", with: "_")).png")
        try? png.write(to: url)
        return try? UNNotificationAttachment(identifier: symbolName, url: url, options: nil)
    }
}
