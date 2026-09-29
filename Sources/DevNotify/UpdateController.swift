import AppKit
import Foundation

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var statusMessage = "Update status has not been checked."
    @Published private(set) var latestCommit: String?
    @Published private(set) var isBusy = false

    private static let repository = "viniciuscodc/devnotify"
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private var timer: Timer?
    private var configuredAutoUpdateValue: Bool?
    private let tokenProvider: () -> String

    let currentCommit: String

    init(bundle: Bundle = .main, tokenProvider: @escaping () -> String = { "" }) {
        currentCommit = bundle.object(forInfoDictionaryKey: "DevNotifyCommitHash") as? String ?? "development"
        self.tokenProvider = tokenProvider
    }

    var currentVersion: String {
        if currentCommit.hasPrefix("development-") {
            return "development (\(Self.shortHash(String(currentCommit.dropFirst("development-".count)))))"
        }
        if currentCommit == "development" { return "development" }
        return Self.shortHash(currentCommit)
    }

    func configure(autoUpdatesEnabled: Bool) {
        guard configuredAutoUpdateValue != autoUpdatesEnabled else { return }
        configuredAutoUpdateValue = autoUpdatesEnabled
        timer?.invalidate()
        timer = nil

        guard autoUpdatesEnabled else {
            statusMessage = "Automatic updates are disabled."
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkForUpdates(installIfAvailable: true, userInitiated: false) }
        }
        Task { await checkForUpdates(installIfAvailable: true, userInitiated: false) }
    }

    func checkManually() {
        Task { await checkForUpdates(installIfAvailable: true, userInitiated: true) }
    }

    nonisolated static func updateAvailable(current: String, latest: String) -> Bool {
        current != latest
    }

    private func checkForUpdates(installIfAvailable: Bool, userInitiated: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Checking viniciuscodc/devnotify…"
        defer { isBusy = false }

        do {
            let latest = try await fetchLatestCommit()
            latestCommit = latest
            guard Self.updateAvailable(current: currentCommit, latest: latest) else {
                statusMessage = "DevNotify is up to date."
                return
            }

            if currentCommit.hasPrefix("development"), !userInitiated {
                statusMessage = "Development build; latest repository commit is \(Self.shortHash(latest))."
                return
            }

            statusMessage = "Installing commit \(Self.shortHash(latest))…"
            if installIfAvailable {
                let installedApp = try await installVersion(latest)
                statusMessage = "Update installed. Relaunching…"
                try relaunch(installedApp)
            } else {
                statusMessage = "Commit \(Self.shortHash(latest)) is available."
            }
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    private func fetchLatestCommit() async throws -> String {
        let token = tokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await fetchLatestCommit(token: token)
        } catch where !token.isEmpty {
            // A token scoped to different repositories can fail for a public
            // updater repository, so retry without authentication.
            return try await fetchLatestCommit(token: "")
        }
    }

    private func fetchLatestCommit(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/commits?per_page=1")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DevNotify", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.checkFailed(http.statusCode) }
        let commits = try JSONDecoder().decode([CommitResponse].self, from: data)
        guard let sha = commits.first?.sha, !sha.isEmpty else { throw UpdateError.invalidResponse }
        return sha
    }

    /// Where the updated app is installed. Installed builds replace themselves in place;
    /// development builds (run from `.build/`) install into ~/Applications instead.
    private var installDirectory: URL {
        if currentCommit.hasPrefix("development") {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        }
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }

    private func installVersion(_ commit: String) async throws -> URL {
        let installDirectory = self.installDirectory
        let destination = installDirectory.appendingPathComponent("DevNotify.app", isDirectory: true)
        // Run the installer from the exact commit being installed, so the script and source always match.
        let command = "set -o pipefail; gh api -H 'Accept: application/vnd.github.raw+json' 'repos/\(Self.repository)/contents/scripts/install.sh?ref=\(commit)' | /bin/zsh"
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("devnotify-update-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
            try? FileManager.default.removeItem(at: logURL)
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            var environment = ProcessInfo.processInfo.environment
            // Apps launched from Finder/login items get a minimal PATH; make gh and swift discoverable.
            let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
            environment["DEVNOTIFY_REPOSITORY"] = Self.repository
            environment["DEVNOTIFY_COMMIT"] = commit
            environment["DEVNOTIFY_INSTALL_DIR"] = installDirectory.path
            environment["DEVNOTIFY_RELAUNCH"] = "0"
            process.environment = environment
            // Write output to a file rather than a pipe so a verbose build can never fill the pipe buffer and hang.
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }

        guard status == 0 else {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let lastLines = output.split(separator: "\n").suffix(3).joined(separator: "\n")
            throw UpdateError.installFailed(lastLines.isEmpty ? "Installer exited with status \(status)." : lastLines)
        }
        return destination
    }

    private func relaunch(_ applicationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", applicationURL.path]
        try process.run()
        NSApplication.shared.terminate(nil)
    }

    private static func shortHash(_ hash: String) -> String { String(hash.prefix(7)) }
}

private struct CommitResponse: Decodable { let sha: String }

private enum UpdateError: LocalizedError {
    case checkFailed(Int)
    case invalidResponse
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .checkFailed(let status): "GitHub did not return the latest repository commit (HTTP \(status))."
        case .invalidResponse: "GitHub returned an invalid commit response."
        case .installFailed(let message): message
        }
    }
}
