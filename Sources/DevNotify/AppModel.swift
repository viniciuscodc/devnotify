import Foundation

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let calendar: CalendarStore
    let pullRequests: PRStore
    private var hotKeys: GlobalHotKeyManager!

    init() {
        let settings = AppSettings()
        self.settings = settings
        calendar = CalendarStore(settings: settings)
        pullRequests = PRStore(settings: settings)
        hotKeys = GlobalHotKeyManager(
            joinMeeting: { [weak self] in self?.calendar.joinCurrentOrNextMeeting() },
            openReady: { [weak self] in self?.pullRequests.openFirstReady() },
            openReview: { [weak self] in self?.pullRequests.openFirstReview() }
        )
        hotKeys.configure(using: settings)
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.calendar.settingsDidChange(); self.pullRequests.settingsDidChange(); self.hotKeys.configure(using: self.settings)
        }
        settings.onCredentialsChange = { [weak self] in self?.pullRequests.credentialsDidChange() }
    }
}
