import Foundation
import SwiftUI
import Combine

/// Isolated to the main actor so every `@Published` mutation (which drives the
/// SwiftUI menu bar) happens on the main thread. Blocking helpers below are
/// `nonisolated` and run off the main thread.
@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var usageByConfigFolderPath: [String: AccountUsage] = [:]

    let accountStore: AccountStore

    private var refreshTimer: Timer?
    private var shownAccountsSubscription: AnyCancellable?
    private let apiURL = URL(string: "https://platform.claude.com/api/oauth/usage")!

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
        shownAccountsSubscription = accountStore.$accounts
            .map { accounts in accounts.filter(\.isShownInMenuBar).map(\.configFolderPath) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
        Task { await self.refreshAndReschedule() }
    }

    // MARK: - Public

    func usage(for account: ClaudeAccount) -> AccountUsage {
        usageByConfigFolderPath[account.configFolderPath] ?? AccountUsage()
    }

    func refresh(force: Bool = false) async {
        let homeFolderPath = ClaudeAccount.currentHomeFolderPath
        let foundConfigFolderPaths = await Task.detached(priority: .userInitiated) {
            Self.findConfigFoldersWithKeychainLogin(homeFolderPath: homeFolderPath)
        }.value
        accountStore.addFoundConfigFolders(foundConfigFolderPaths)

        await withTaskGroup(of: Void.self) { group in
            for account in accountStore.accounts {
                group.addTask { await self.refresh(account: account, force: force) }
            }
        }
    }

    private func refresh(account: ClaudeAccount, force: Bool) async {
        let configFolderPath = account.configFolderPath
        let keychainServiceName = account.keychainServiceName

        guard account.isShownInMenuBar else {
            let keychainLoginStatus = await Task.detached(priority: .utility) {
                Self.readKeychainLoginStatus(keychainServiceName: keychainServiceName)
            }.value
            usageByConfigFolderPath[configFolderPath, default: AccountUsage()].keychainLoginStatus = keychainLoginStatus
            return
        }

        let projectsFolderURL = account.projectsFolderURL
        async let activityTask = Task.detached(priority: .userInitiated) {
            await Self.parseLocalTokenHistory(projectsFolderURL: projectsFolderURL)
        }.value

        let lastUpdated = usageByConfigFolderPath[configFolderPath]?.lastUpdated
        let skipNetwork = !force && lastUpdated.map { Date().timeIntervalSince($0) < 60 } ?? false

        if !skipNetwork {
            usageByConfigFolderPath[configFolderPath, default: AccountUsage()].loadState = .loading
            do {
                let (token, plan) = try await Task.detached(priority: .userInitiated) {
                    try Self.fetchOAuthToken(keychainServiceName: keychainServiceName)
                }.value
                usageByConfigFolderPath[configFolderPath, default: AccountUsage()].keychainLoginStatus = .found
                let response = try await fetchUsage(token: token)
                var usage = usageByConfigFolderPath[configFolderPath] ?? AccountUsage()
                usage.windows = response.windows
                usage.extraUsage = response.extraUsage
                usage.planName = plan
                usage.lastUpdated = Date()
                usage.loadState = .loaded
                usageByConfigFolderPath[configFolderPath] = usage
            } catch let error as UsageError {
                var usage = usageByConfigFolderPath[configFolderPath] ?? AccountUsage()
                if let keychainLoginStatus = error.keychainLoginStatus {
                    usage.keychainLoginStatus = keychainLoginStatus
                }
                usage.loadState = .error(error.localizedDescription)
                usageByConfigFolderPath[configFolderPath] = usage
            } catch {
                usageByConfigFolderPath[configFolderPath, default: AccountUsage()].loadState = .error(error.localizedDescription)
            }
        }

        let activity = await activityTask
        var usage = usageByConfigFolderPath[configFolderPath] ?? AccountUsage()
        usage.tokenActivity = activity
        usage.tokenActivityLoaded = true
        usageByConfigFolderPath[configFolderPath] = usage
    }

    private var isEveryShownAccountLoaded: Bool {
        accountStore.shownAccounts.allSatisfy { usage(for: $0).hasUsageData }
    }

    private nonisolated static func findConfigFoldersWithKeychainLogin(homeFolderPath: String) -> [String] {
        let folderNames = (try? FileManager.default.contentsOfDirectory(atPath: homeFolderPath)) ?? []
        return folderNames
            .filter(ClaudeAccount.isConfigFolderName)
            .map { (homeFolderPath as NSString).appendingPathComponent($0) }
            .filter(isExistingFolder)
            .filter { configFolderPath in
                hasKeychainEntry(keychainServiceName: ClaudeAccount.keychainServiceName(
                    configFolderPath: configFolderPath,
                    homeFolderPath: homeFolderPath
                ))
            }
            .sorted()
    }

    nonisolated static func isExistingFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private nonisolated static func hasKeychainEntry(keychainServiceName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainServiceName]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Keychain

    private nonisolated static func readKeychainLoginStatus(keychainServiceName: String) -> KeychainLoginStatus {
        do {
            _ = try fetchOAuthToken(keychainServiceName: keychainServiceName)
            return .found
        } catch let error as UsageError {
            return error.keychainLoginStatus ?? .unreadable
        } catch {
            return .unreadable
        }
    }

    private nonisolated static func fetchOAuthToken(keychainServiceName: String) throws -> (String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainServiceName, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UsageError.keychainNotFound
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw UsageError.keychainNotFound
        }

        guard let jsonData = raw.data(using: .utf8) else {
            throw UsageError.invalidToken
        }

        if let creds = try? JSONDecoder().decode(OAuthCredentials.self, from: jsonData),
           let oauth = creds.claudeAiOauth {
            // Check expiry
            if let exp = oauth.expiresAt, exp < Date().timeIntervalSince1970 * 1000 {
                throw UsageError.tokenExpired
            }
            let plan = oauth.subscriptionType?.capitalized ?? "Pro"
            return (oauth.accessToken, plan)
        }

        throw UsageError.invalidToken
    }

    // MARK: - API

    private nonisolated func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.x", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.networkError("Invalid response")
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw UsageError.networkError("HTTP \(http.statusCode): \(body)")
        }

        return try UsageResponse.decode(from: data)
    }

    // MARK: - Token History (JSONL)

    /// Per-file parse output — collapsed into one `TokenActivity` at the end.
    private struct FileParseResult {
        var todayTokens: Int = 0
        var last3DaysTokens: Int = 0
        var last7DaysTokens: Int = 0
        var todayInputTokens: Int = 0
        var todayOutputTokens: Int = 0
        var todayCacheCreationTokens: Int = 0
        var todayCacheReadTokens: Int = 0
        var sessions: [String: SessionAccum] = [:]
        var latestModel: String? = nil
        var latestModelTimestamp: Date = .distantPast
    }

    private struct SessionAccum {
        var model: String
        var cwd: String?
        var lastActivity: Date
    }

    /// Scans `.jsonl` files modified in the last 10 days concurrently via TaskGroup.
    /// Each message's own timestamp decides which window (today / 3d / 7d) it
    /// contributes to — file mod-date is just a gate to skip old files.
    private nonisolated static func parseLocalTokenHistory(projectsFolderURL: URL) async -> TokenActivity {
        guard FileManager.default.fileExists(atPath: projectsFolderURL.path) else { return TokenActivity() }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let start3Days = startOfToday.addingTimeInterval(-2 * 86_400)
        let start7Days = startOfToday.addingTimeInterval(-6 * 86_400)
        let sessionCutoff = now.addingTimeInterval(-10 * 86_400)

        // Gather candidate files first — the same cutoff covers the 7-day token
        // windows and the 10-day session window (pick the earlier).
        let fileCutoff = sessionCutoff
        var fileURLs: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: projectsFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modDate < fileCutoff { continue }
            fileURLs.append(url)
        }

        // Parse each file concurrently.
        let results: [FileParseResult] = await withTaskGroup(of: FileParseResult.self) { group in
            for url in fileURLs {
                group.addTask {
                    parseFile(url: url,
                              startOfToday: startOfToday,
                              start3Days: start3Days,
                              start7Days: start7Days)
                }
            }
            var collected: [FileParseResult] = []
            collected.reserveCapacity(fileURLs.count)
            for await r in group { collected.append(r) }
            return collected
        }

        // Merge.
        var activity = TokenActivity()
        var mergedSessions: [String: SessionAccum] = [:]
        var latestModel: String? = nil
        var latestModelTs: Date = .distantPast

        for r in results {
            activity.todayTokens += r.todayTokens
            activity.last3DaysTokens += r.last3DaysTokens
            activity.last7DaysTokens += r.last7DaysTokens
            activity.todayInputTokens += r.todayInputTokens
            activity.todayOutputTokens += r.todayOutputTokens
            activity.todayCacheCreationTokens += r.todayCacheCreationTokens
            activity.todayCacheReadTokens += r.todayCacheReadTokens
            if let model = r.latestModel, r.latestModelTimestamp > latestModelTs {
                latestModel = model
                latestModelTs = r.latestModelTimestamp
            }
            for (sid, acc) in r.sessions {
                if let existing = mergedSessions[sid] {
                    if acc.lastActivity > existing.lastActivity { mergedSessions[sid] = acc }
                } else {
                    mergedSessions[sid] = acc
                }
            }
        }

        activity.currentModel = latestModel

        // Dedupe sessions by project name (most recent wins), keep last 10 days.
        var byProject: [String: SessionSummary] = [:]
        for (id, acc) in mergedSessions where acc.lastActivity >= sessionCutoff {
            let project = acc.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "(unknown)"
            let summary = SessionSummary(id: id, projectName: project, model: acc.model, lastActivity: acc.lastActivity)
            if let existing = byProject[project] {
                if summary.lastActivity > existing.lastActivity {
                    byProject[project] = summary
                }
            } else {
                byProject[project] = summary
            }
        }
        activity.recentSessions = byProject.values.sorted { $0.lastActivity > $1.lastActivity }

        return activity
    }

    /// Parses a single JSONL file and returns its contribution. Pure / thread-safe.
    private nonisolated static func parseFile(url: URL, startOfToday: Date, start3Days: Date, start7Days: Date) -> FileParseResult {
        var result = FileParseResult()
        guard let lines = readTailLines(of: url) else { return result }
        var seenIDs = Set<String>()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterBasic = ISO8601DateFormatter()
        isoFormatterBasic.formatOptions = [.withInternetDateTime]

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(JSONLMessage.self, from: lineData),
                  msg.type == "assistant",
                  let message = msg.message else { continue }

            var msgDate: Date? = nil
            if let ts = msg.timestamp {
                let cleaned = ts.hasSuffix("Z") ? String(ts.dropLast()) + "+00:00" : ts
                msgDate = isoFormatter.date(from: cleaned) ?? isoFormatterBasic.date(from: cleaned)
            }

            if let model = message.model, let date = msgDate, date > result.latestModelTimestamp {
                result.latestModel = model
                result.latestModelTimestamp = date
            }

            if let sid = msg.sessionId, let model = message.model, let date = msgDate {
                if let existing = result.sessions[sid] {
                    if date > existing.lastActivity {
                        result.sessions[sid] = SessionAccum(model: model, cwd: msg.cwd ?? existing.cwd, lastActivity: date)
                    }
                } else {
                    result.sessions[sid] = SessionAccum(model: model, cwd: msg.cwd, lastActivity: date)
                }
            }

            guard let usage = message.usage, let date = msgDate else { continue }
            if let id = message.id {
                if seenIDs.contains(id) { continue }
                seenIDs.insert(id)
            }

            let input = usage.inputTokens ?? 0
            let output = usage.outputTokens ?? 0
            let cacheCreate = usage.cacheCreationInputTokens ?? 0
            let cacheRead = usage.cacheReadInputTokens ?? 0
            let total = input + output + cacheCreate + cacheRead

            if date >= start7Days { result.last7DaysTokens += total }
            if date >= start3Days { result.last3DaysTokens += total }
            if date >= startOfToday {
                result.todayTokens += total
                result.todayInputTokens += input
                result.todayOutputTokens += output
                result.todayCacheCreationTokens += cacheCreate
                result.todayCacheReadTokens += cacheRead
            }
        }

        return result
    }

    /// Reads up to the last ~128 KB of a JSONL file without loading the whole thing.
    /// Trades a small amount of precision (token totals may miss very long sessions)
    /// for much faster parsing — the recent entries are what we need for display.
    private nonisolated static func readTailLines(of url: URL, maxBytes: UInt64 = 128 * 1024) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let end = try handle.seekToEnd()
            let offset: UInt64 = end > maxBytes ? end - maxBytes : 0
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), let str = String(data: data, encoding: .utf8) else {
                return nil
            }
            var parts = str.components(separatedBy: "\n")
            // If we started mid-file, the first slice is likely a partial line — drop it.
            if offset > 0, !parts.isEmpty {
                parts.removeFirst()
            }
            return parts.filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }

    // MARK: - Timer

    /// Runs a refresh, then schedules the next one. Interval is adaptive:
    /// 15s when we have no data (so we catch up quickly after a re-login),
    /// 60s once usage data is loaded.
    private func refreshAndReschedule() async {
        await refresh()
        scheduleNextRefresh()
    }

    private func scheduleNextRefresh() {
        Task { @MainActor in
            self.refreshTimer?.invalidate()
            let interval: TimeInterval = self.isEveryShownAccountLoaded ? 60 : 15
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshAndReschedule() }
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case keychainNotFound
    case tokenExpired
    case invalidToken
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .keychainNotFound:
            return "Claude Code credentials not found in Keychain. Make sure you're logged in to Claude Code."
        case .tokenExpired:
            return "Claude Code login token expired. Use Claude Code with this account once to refresh it."
        case .invalidToken:
            return "Could not parse OAuth token from Keychain."
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }

    var keychainLoginStatus: KeychainLoginStatus? {
        switch self {
        case .keychainNotFound:
            return .notFound
        case .tokenExpired:
            return .tokenExpired
        case .invalidToken:
            return .unreadable
        case .networkError:
            return nil
        }
    }
}
