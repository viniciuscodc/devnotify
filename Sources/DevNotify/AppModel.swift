import Foundation

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let calendar: CalendarStore
    let pullRequests: PRStore
    let updater: UpdateController
    private var hotKeys: GlobalHotKeyManager!

    init() {
        let settings = AppSettings()
        self.settings = settings
        calendar = CalendarStore(settings: settings)
        pullRequests = PRStore(settings: settings)
        updater = UpdateController(tokenProvider: { settings.token })
        hotKeys = GlobalHotKeyManager(
            joinMeeting: { [weak self] in self?.calendar.joinCurrentOrNextMeeting() },
            openReady: { [weak self] in self?.pullRequests.openFirstReady() },
            openReview: { [weak self] in self?.pullRequests.openFirstReview() }
        )
        hotKeys.configure(using: settings)
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.calendar.settingsDidChange(); self.pullRequests.settingsDidChange(); self.hotKeys.configure(using: self.settings)
            self.updater.configure(autoUpdatesEnabled: self.settings.autoUpdatesEnabled)
        }
        settings.onCredentialsChange = { [weak self] in self?.pullRequests.credentialsDidChange() }
        updater.configure(autoUpdatesEnabled: settings.autoUpdatesEnabled)
    }
}
