import Foundation
import Testing
@testable import DevNotify

@Test func categorizationHonorsRulesAndIgnoreList() {
    let mine = makePR(id: 1, author: true, approved: true, ci: .passed)
    let theirs = makePR(id: 2, author: false, approved: false, ci: .passed)
    let waiting = makePR(id: 3, author: true, approved: false, ci: .failed)
    #expect(PRCategory.ready(from: [mine, theirs, waiting], ignoring: []).map(\.id) == [1])
    #expect(PRCategory.review(from: [mine, theirs, waiting], ignoring: []).map(\.id) == [2])
    #expect(PRCategory.needsReview(from: [mine, theirs, waiting], ignoring: []).map(\.id) == [3])
    #expect(PRCategory.ready(from: [mine], ignoring: [1]).isEmpty)
}

@Test func dependabotIsExcludedAndReviewsAreNewestFirst() {
    let older = makePR(id: 1, author: false, approved: false, ci: .passed, updatedAt: Date(timeIntervalSince1970: 100))
    let newer = makePR(id: 2, author: false, approved: false, ci: .passed, updatedAt: Date(timeIntervalSince1970: 200))
    let bot = makePR(id: 3, author: false, approved: false, ci: .passed, login: "dependabot[bot]")
    #expect(PRCategory.review(from: [older, bot, newer], ignoring: []).map(\.id) == [2, 1])
}

@Test func ciStateAggregation() {
    #expect(GitHubClient.ciState(status: .init(state: "success"), checks: .init(checkRuns: [])) == .passed)
    #expect(GitHubClient.ciState(status: .init(state: "pending"), checks: .init(checkRuns: [])) == .running)
    #expect(GitHubClient.ciState(status: .init(state: "success"), checks: .init(checkRuns: [.init(status: "completed", conclusion: "failure")])) == .failed)
}

@Test func latestReviewStateWins() {
    let reviews = [Review(id: 1, user: .init(login: "alice"), state: "CHANGES_REQUESTED"),
                   Review(id: 2, user: .init(login: "alice"), state: "APPROVED")]
    #expect(GitHubClient.isApproved(reviews: reviews))
}

@Test func commitHashDeterminesUpdateAvailability() {
    let current = "0123456789abcdef"
    #expect(!UpdateController.updateAvailable(current: current, latest: current))
    #expect(UpdateController.updateAvailable(current: current, latest: "fedcba9876543210"))
}

private func makePR(id: Int, author: Bool, approved: Bool, ci: CIState, updatedAt: Date = .now, login: String = "dev") -> PullRequest {
    PullRequest(id: id, number: id, title: "PR", repository: "org/repo", authorLogin: login, authorAvatarURL: nil,
        url: URL(string: "https://github.com/org/repo/pull/\(id)")!, headSHA: "sha", updatedAt: updatedAt,
        isAuthor: author, isApproved: approved, isDraft: false, ciState: ci)
}
