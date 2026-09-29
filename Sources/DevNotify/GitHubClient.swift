import Foundation

struct GitHubClient {
    private let token: String
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }()
    private let baseURL = URL(string: "https://api.github.com")!

    init(token: String) { self.token = token }

    func fetchPullRequests(targets: [String]) async throws -> (login: String, pullRequests: [PullRequest]) {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitHubError.missingToken }
        let user: APIUser = try await get(path: "/user")
        let queries: [String] = targets.isEmpty
            ? ["author:@me", "assignee:@me", "review-requested:@me"].map { "is:pr is:open archived:false \($0)" }
            : targets.map { target in
                let qualifier = target.hasPrefix("org:") || target.hasPrefix("repo:") ? target : (target.contains("/") ? "repo:\(target)" : "org:\(target)")
                return "is:pr is:open archived:false \(qualifier)"
            }
        var found: [Int: SearchItem] = [:]
        for query in queries {
            let result: SearchResponse = try await get(path: "/search/issues", query: ["q": query, "per_page": "100"])
            for item in result.items where item.pullRequest != nil { found[item.id] = item }
        }
        var pullRequests: [PullRequest] = []
        for item in found.values {
            guard let coordinates = repositoryCoordinates(from: item.repositoryURL) else { continue }
            async let detail: APIPullRequest = get(path: "/repos/\(coordinates.owner)/\(coordinates.repo)/pulls/\(item.number)")
            async let reviews: [Review] = get(path: "/repos/\(coordinates.owner)/\(coordinates.repo)/pulls/\(item.number)/reviews", query: ["per_page": "100"])
            let pr = try await detail
            async let status: CombinedStatus = get(path: "/repos/\(coordinates.owner)/\(coordinates.repo)/commits/\(pr.head.sha)/status")
            async let checks: CheckRunsResponse = get(path: "/repos/\(coordinates.owner)/\(coordinates.repo)/commits/\(pr.head.sha)/check-runs", query: ["per_page": "100"])
            let reviewList = try await reviews
            pullRequests.append(PullRequest(
                id: pr.id, number: pr.number, title: pr.title, repository: "\(coordinates.owner)/\(coordinates.repo)",
                authorLogin: pr.user.login, authorAvatarURL: pr.user.avatarURL, url: pr.htmlURL, headSHA: pr.head.sha,
                updatedAt: pr.updatedAt, isAuthor: pr.user.login.caseInsensitiveCompare(user.login) == .orderedSame,
                isApproved: Self.isApproved(reviews: reviewList), isDraft: pr.draft,
                ciState: try await Self.ciState(status: status, checks: checks),
                reviews: reviewList.filter { $0.state != "PENDING" }.map { .init(id: $0.id, reviewer: $0.user.login, state: $0.state) }
            ))
        }
        return (user.login, pullRequests.sorted { $0.updatedAt > $1.updatedAt })
    }

    func merge(_ pullRequest: PullRequest) async throws {
        struct MergeBody: Encodable { let sha: String; let merge_method = "merge" }
        struct MergeResult: Decodable { let merged: Bool; let message: String }
        let result: MergeResult = try await send(path: "/repos/\(pullRequest.repository)/pulls/\(pullRequest.number)/merge",
            method: "PUT", body: MergeBody(sha: pullRequest.headSHA))
        guard result.merged else { throw GitHubError.api(result.message) }
    }

    func rerunFailedCI(for pullRequest: PullRequest) async throws -> Int {
        let response: WorkflowRunsResponse = try await get(path: "/repos/\(pullRequest.repository)/actions/runs",
            query: ["head_sha": pullRequest.headSHA, "status": "failure", "per_page": "100"])
        guard !response.workflowRuns.isEmpty else { throw GitHubError.api("No failed GitHub Actions runs were found for this commit.") }
        for run in response.workflowRuns {
            try await sendWithoutResponse(path: "/repos/\(pullRequest.repository)/actions/runs/\(run.id)/rerun-failed-jobs", method: "POST")
        }
        return response.workflowRuns.count
    }

    static func ciState(status: CombinedStatus, checks: CheckRunsResponse) -> CIState {
        let failed = Set(["failure", "cancelled", "timed_out", "action_required", "stale", "startup_failure"])
        if status.state == "failure" || status.state == "error" || checks.checkRuns.contains(where: { failed.contains($0.conclusion ?? "") }) { return .failed }
        if status.state == "pending" || checks.checkRuns.contains(where: { $0.status != "completed" || $0.conclusion == nil }) { return .running }
        return .passed
    }

    static func isApproved(reviews: [Review]) -> Bool {
        var latestByUser: [String: String] = [:]
        for review in reviews where review.state != "COMMENTED" && review.state != "PENDING" { latestByUser[review.user.login.lowercased()] = review.state }
        return latestByUser.values.contains("APPROVED") && !latestByUser.values.contains("CHANGES_REQUESTED")
    }

    private func repositoryCoordinates(from url: URL) -> (owner: String, repo: String)? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[0] == "repos" else { return nil }
        return (parts[1], parts[2])
    }
    private func get<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        try await send(path: path, method: "GET", query: query, body: Optional<String>.none)
    }
    private func send<Body: Encodable, Result: Decodable>(path: String, method: String, query: [String: String] = [:], body: Body?) async throws -> Result {
        let (data, response) = try await perform(path: path, method: method, query: query, body: body)
        guard (200..<300).contains(response.statusCode) else { throw decodeError(data: data, status: response.statusCode) }
        do { return try decoder.decode(Result.self, from: data) } catch { throw GitHubError.invalidResponse(error.localizedDescription) }
    }
    private func sendWithoutResponse(path: String, method: String) async throws {
        let (data, response) = try await perform(path: path, method: method, query: [:], body: Optional<String>.none)
        guard (200..<300).contains(response.statusCode) else { throw decodeError(data: data, status: response.statusCode) }
    }
    private func perform<Body: Encodable>(path: String, method: String, query: [String: String], body: Body?) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map(URLQueryItem.init) }
        var request = URLRequest(url: components.url!); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse("GitHub returned a non-HTTP response.") }
        return (data, http)
    }
    private func decodeError(data: Data, status: Int) -> Error {
        let message = (try? decoder.decode(APIError.self, from: data).message) ?? HTTPURLResponse.localizedString(forStatusCode: status)
        return GitHubError.api("GitHub \(status): \(message)")
    }
}

enum GitHubError: LocalizedError {
    case missingToken, api(String), invalidResponse(String)
    var errorDescription: String? {
        switch self { case .missingToken: "Add a GitHub personal access token in Settings."; case .api(let value), .invalidResponse(let value): value }
    }
}

private struct APIError: Decodable { let message: String }
private struct APIUser: Decodable {
    let login: String; let avatarURL: URL?
    enum CodingKeys: String, CodingKey { case login; case avatarURL = "avatar_url" }
}
private struct SearchResponse: Decodable { let items: [SearchItem] }
private struct SearchItem: Decodable {
    let id: Int; let number: Int; let repositoryURL: URL; let pullRequest: PullRequestMarker?
    enum CodingKeys: String, CodingKey { case id, number; case repositoryURL = "repository_url"; case pullRequest = "pull_request" }
}
private struct PullRequestMarker: Decodable {}
private struct APIPullRequest: Decodable {
    let id: Int; let number: Int; let title: String; let htmlURL: URL; let user: APIUser; let head: Head; let draft: Bool; let updatedAt: Date
    struct Head: Decodable { let sha: String }
    enum CodingKeys: String, CodingKey { case id, number, title, user, head, draft; case htmlURL = "html_url"; case updatedAt = "updated_at" }
}
struct Review: Decodable {
    let id: Int; let user: ReviewUser; let state: String
    struct ReviewUser: Decodable { let login: String }
}
struct CombinedStatus: Decodable { let state: String }
struct CheckRunsResponse: Decodable {
    let checkRuns: [CheckRun]
    struct CheckRun: Decodable { let status: String; let conclusion: String? }
    enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" }
}
private struct WorkflowRunsResponse: Decodable { let workflowRuns: [WorkflowRun]; enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" } }
private struct WorkflowRun: Decodable { let id: Int }
