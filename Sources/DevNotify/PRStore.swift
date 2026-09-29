import AppKit
import Foundation

@MainActor
final class PRStore: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var ignoredIDs: Set<Int>
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionMessage: String?
    @Published private(set) var authenticatedLogin: String?

    let settings: AppSettings
    private var pollTimer: Timer?
    private var credentialsRefreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var knownReadyIDs: Set<Int>?
    private var knownReviewIDs: Set<Int>?

    private var filteredPullRequests: [PullRequest] {
        let users = settings.parsedFilteredUsers
        return pullRequests.filter { !$0.isDependabot && (users.isEmpty || users.contains($0.authorLogin.lowercased())) }
    }
    var ready: [PullRequest] { PRCategory.ready(from: filteredPullRequests, ignoring: ignoredIDs) }
    var review: [PullRequest] { PRCategory.review(from: filteredPullRequests, ignoring: ignoredIDs) }
    var needsReview: [PullRequest] { PRCategory.needsReview(from: filteredPullRequests, ignoring: ignoredIDs) }
    var ignored: [PullRequest] { filteredPullRequests.filter { ignoredIDs.contains($0.id) } }

    init(settings: AppSettings) {
        self.settings = settings
        ignoredIDs = Set(UserDefaults.standard.array(forKey: "ignoredPullRequestIDs") as? [Int] ?? [])
        configurePolling()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { refreshRequested = true; return }
        isLoading = true
        defer {
            isLoading = false
            if refreshRequested { refreshRequested = false; Task { await refresh() } }
        }
        do {
            let result = try await GitHubClient(token: settings.token).fetchPullRequests(targets: settings.parsedTargets)
            authenticatedLogin = result.login; pullRequests = result.pullRequests; errorMessage = nil
            notifyForChanges()
        } catch { errorMessage = error.localizedDescription }
    }

    func merge(_ pullRequest: PullRequest) async {
        await perform(message: "Merged #\(pullRequest.number) in \(pullRequest.repository)") { try await GitHubClient(token: settings.token).merge(pullRequest) }
    }
    func rerunFailedCI(_ pullRequest: PullRequest) async {
        do {
            let count = try await GitHubClient(token: settings.token).rerunFailedCI(for: pullRequest)
            actionMessage = "Re-running failed jobs in \(count) workflow\(count == 1 ? "" : "s")."; errorMessage = nil
            try? await Task.sleep(nanoseconds: 1_000_000_000); await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func ignore(_ pullRequest: PullRequest) { ignoredIDs.insert(pullRequest.id); persistIgnored() }
    func restore(_ pullRequest: PullRequest) { ignoredIDs.remove(pullRequest.id); persistIgnored() }
    func open(_ pullRequest: PullRequest) { NSWorkspace.shared.open(pullRequest.url) }
    func openFirstReady() { if let first = ready.first { open(first) } }
    func openFirstReview() { if let first = review.first { open(first) } }

    func settingsDidChange() { configurePolling(); objectWillChange.send() }
    func credentialsDidChange() {
        configurePolling(); knownReadyIDs = nil; knownReviewIDs = nil; credentialsRefreshTask?.cancel()
        credentialsRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000); guard !Task.isCancelled else { return }; await self?.refresh()
        }
    }

    private func perform(message: String, action: () async throws -> Void) async {
        do { try await action(); actionMessage = message; errorMessage = nil; await refresh() } catch { errorMessage = error.localizedDescription }
    }
    private func configurePolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Double(settings.pollMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
    private func notifyForChanges() {
        let currentReady = Set(ready.map(\.id))
        let authored = pullRequests.filter(\.isAuthor)
        let currentReviewIDs = Set(authored.flatMap(\.reviews).map(\.id))
        defer { knownReadyIDs = currentReady; knownReviewIDs = currentReviewIDs }
        guard !settings.notificationsMuted else { return }
        if let knownReadyIDs {
            for pullRequest in ready where !knownReadyIDs.contains(pullRequest.id) { NotificationService.ready(pullRequest) }
        }
        if settings.reviewNotificationsEnabled, let knownReviewIDs {
            for pullRequest in authored {
                for review in pullRequest.reviews where !knownReviewIDs.contains(review.id) {
                    NotificationService.reviewed(pullRequest, review: review)
                }
            }
        }
    }
    private func persistIgnored() { UserDefaults.standard.set(Array(ignoredIDs), forKey: "ignoredPullRequestIDs") }
}
