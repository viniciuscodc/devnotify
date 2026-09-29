import AppKit
import EventKit
import Foundation

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authorizationError: String?
    @Published private(set) var isLoading = false
    @Published var now = Date()
    @Published private(set) var ignoredEventIDs: Set<String>

    private let eventStore = EKEventStore()
    private let settings: AppSettings
    private var timer: Timer?
    private var eventStoreObserver: NSObjectProtocol?

    private var activeEvents: [CalendarEvent] { events.filter { !ignoredEventIDs.contains($0.id) } }
    var currentEvents: [CalendarEvent] { activeEvents.filter { $0.startDate <= now && $0.endDate > now } }
    var current: CalendarEvent? { currentEvents.first }
    var next: CalendarEvent? { activeEvents.first { $0.startDate > now } }
    var upcoming: [CalendarEvent] { activeEvents.filter { $0.startDate > now }.prefix(5).map { $0 } }
    var ignoredEvents: [CalendarEvent] { events.filter { ignoredEventIDs.contains($0.id) && $0.endDate > now } }

    init(settings: AppSettings) {
        self.settings = settings
        ignoredEventIDs = Set(UserDefaults.standard.stringArray(forKey: "ignoredEventIDs") ?? [])
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        eventStoreObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    deinit { if let eventStoreObserver { NotificationCenter.default.removeObserver(eventStoreObserver) } }

    func tick() { now = Date(); scheduleNotifications() }

    func refresh() async {
        isLoading = true; defer { isLoading = false; now = Date() }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else { authorizationError = "Calendar access is required to show your schedule."; return }
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
                .filter { $0.status != .canceled }.map(CalendarEvent.init).sorted { $0.startDate < $1.startDate }
            ignoredEventIDs.formIntersection(Set(events.map(\.id))); persistIgnoredEvents()
            authorizationError = nil
            scheduleNotifications(requestAuthorization: true)
        } catch { authorizationError = error.localizedDescription }
    }

    func syncAndRefresh() async { eventStore.refreshSourcesIfNecessary(); await refresh() }
    func ignore(_ event: CalendarEvent) { ignoredEventIDs.insert(event.id); persistIgnoredEvents(); scheduleNotifications() }
    func restore(_ event: CalendarEvent) { ignoredEventIDs.remove(event.id); persistIgnoredEvents(); scheduleNotifications() }
    func settingsDidChange() { scheduleNotifications() }

    func joinCurrentOrNextMeeting() {
        let event = currentEvents.first ?? activeEvents.first { $0.startDate > now && $0.videoURL != nil }
        if let url = event?.videoURL { NSWorkspace.shared.open(url) }
    }

    private func scheduleNotifications(requestAuthorization: Bool = false) {
        let eligible = activeEvents.filter { $0.startDate > now && !$0.isAllDay && $0.response != .declined }
        NotificationService.scheduleMeetings(eligible, minutesBefore: settings.reminderMinutes,
                                             muted: settings.notificationsMuted, requestAuthorization: requestAuthorization)
    }
    private func persistIgnoredEvents() { UserDefaults.standard.set(Array(ignoredEventIDs), forKey: "ignoredEventIDs") }
}
