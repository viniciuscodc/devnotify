import Foundation

enum CIState: String, Codable, CaseIterable {
    case passed, failed, running
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .passed: "checkmark.circle.fill"; case .failed: "xmark.circle.fill"; case .running: "clock.arrow.circlepath" }
    }
}

struct PullRequestReview: Codable, Equatable, Hashable {
    let id: Int
    let reviewer: String
    let state: String
}

struct PullRequest: Identifiable, Codable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let repository: String
    let authorLogin: String
    let authorAvatarURL: URL?
    let url: URL
    let headSHA: String
    let updatedAt: Date
    let isAuthor: Bool
    let isApproved: Bool
    let isDraft: Bool
    let ciState: CIState
    let reviews: [PullRequestReview]

    init(id: Int, number: Int, title: String, repository: String, authorLogin: String, authorAvatarURL: URL?, url: URL,
         headSHA: String, updatedAt: Date, isAuthor: Bool, isApproved: Bool, isDraft: Bool, ciState: CIState,
         reviews: [PullRequestReview] = []) {
        self.id = id; self.number = number; self.title = title; self.repository = repository
        self.authorLogin = authorLogin; self.authorAvatarURL = authorAvatarURL; self.url = url; self.headSHA = headSHA
        self.updatedAt = updatedAt; self.isAuthor = isAuthor; self.isApproved = isApproved; self.isDraft = isDraft
        self.ciState = ciState; self.reviews = reviews
    }

    var isReadyToMerge: Bool { isAuthor && isApproved && !isDraft && ciState == .passed }
    var isReviewable: Bool { !isAuthor && !isDraft && ciState == .passed }
    var needsReview: Bool { isAuthor && !isApproved && !isDraft }
    var isDependabot: Bool { authorLogin.lowercased().hasPrefix("dependabot") }
}

enum PRCategory {
    static func ready(from pullRequests: [PullRequest], ignoring ids: Set<Int>) -> [PullRequest] {
        pullRequests.filter { !$0.isDependabot && !ids.contains($0.id) && $0.isReadyToMerge }
    }
    static func review(from pullRequests: [PullRequest], ignoring ids: Set<Int>) -> [PullRequest] {
        pullRequests.filter { !$0.isDependabot && !ids.contains($0.id) && $0.isReviewable }.sorted { $0.updatedAt > $1.updatedAt }
    }
    static func needsReview(from pullRequests: [PullRequest], ignoring ids: Set<Int>) -> [PullRequest] {
        pullRequests.filter { !$0.isDependabot && !ids.contains($0.id) && $0.needsReview }
    }
}
