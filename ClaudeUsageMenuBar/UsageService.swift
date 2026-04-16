import Foundation
import SwiftUI

@Observable
final class UsageService {
    var loadState: UsageLoadState = .idle
    var windows: [String: UsageWindow] = [:]
    var extraUsage: ExtraUsage? = nil
    var tokenActivity: TokenActivity = TokenActivity()
    var lastUpdated: Date? = nil
    var planName: String = "Pro"

    private var refreshTimer: Timer?
    private let apiURL = URL(string: "https://platform.claude.com/api/oauth/usage")!

    init() {
        Task { await refresh() }
        startAutoRefresh()
    }

    // MARK: - Public

    func refresh(force: Bool = false) async {
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < 60 {
            return
        }
        loadState = .loading
        do {
            let (token, plan) = try fetchOAuthToken()
            let response = try await fetchUsage(token: token)
            await MainActor.run {
                self.windows = response.windows
                self.extraUsage = response.extraUsage
                self.planName = plan
                self.lastUpdated = Date()
                self.loadState = .loaded
            }
        } catch {
            await MainActor.run {
                if case .loaded = self.loadState {
                    // Keep showing stale data, just update error
                } else {
                    self.loadState = .error(error.localizedDescription)
                }
            }
        }

        // Token history is non-critical
        let activity = parseLocalTokenHistory()
        await MainActor.run {
            self.tokenActivity = activity
        }
    }

    // MARK: - Computed Helpers

    var sessionWindow: UsageWindow? {
        windows["five_hour"]
    }

    var weeklyWindow: UsageWindow? {
        windows["seven_day"]
    }

    var secondaryWindows: [WindowDisplayInfo] {
        let primaryKeys: Set<String> = ["five_hour", "seven_day"]
        return windows
            .filter { !primaryKeys.contains($0.key) }
            .map { WindowDisplayInfo(key: $0.key, window: $0.value) }
            .sorted { $0.label < $1.label }
    }

    var menuBarRemaining: Double {
        sessionWindow?.remaining ?? 100
    }

    // MARK: - Keychain

    private func fetchOAuthToken() throws -> (String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

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
                throw UsageError.invalidToken
            }
            let plan = oauth.subscriptionType?.capitalized ?? "Pro"
            return (oauth.accessToken, plan)
        }

        throw UsageError.invalidToken
    }

    // MARK: - API

    private func fetchUsage(token: String) async throws -> UsageResponse {
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

    private func parseLocalTokenHistory() -> TokenActivity {
        var activity = TokenActivity()
        var seenIDs = Set<String>()

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = homeDir.appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            return activity
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        // Collect all JSONL files with modification dates
        var jsonlFiles: [(url: URL, modDate: Date)] = []
        let enumerator = FileManager.default.enumerator(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            jsonlFiles.append((url: fileURL, modDate: modDate))
        }
        // Sort newest first so we detect current model from the most recent file
        jsonlFiles.sort { $0.modDate > $1.modDate }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFormatterBasic = ISO8601DateFormatter()
        isoFormatterBasic.formatOptions = [.withInternetDateTime]

        var latestModel: String? = nil
        var latestModelTimestamp: Date = .distantPast

        for (fileURL, _) in jsonlFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: .newlines) {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8) else { continue }

                guard let msg = try? JSONDecoder().decode(JSONLMessage.self, from: lineData) else { continue }

                guard msg.type == "assistant",
                      let message = msg.message else { continue }

                // Parse timestamp
                var msgDate: Date? = nil
                if let ts = msg.timestamp {
                    let cleaned = ts.hasSuffix("Z") ? String(ts.dropLast()) + "+00:00" : ts
                    msgDate = isoFormatter.date(from: cleaned)
                        ?? isoFormatterBasic.date(from: cleaned)
                }

                // Track the most recent model
                if let model = message.model, let date = msgDate, date > latestModelTimestamp {
                    latestModel = model
                    latestModelTimestamp = date
                }

                guard let usage = message.usage else { continue }

                if let id = message.id {
                    guard !seenIDs.contains(id) else { continue }
                    seenIDs.insert(id)
                }

                let input = usage.inputTokens ?? 0
                let output = usage.outputTokens ?? 0
                let cacheCreate = usage.cacheCreationInputTokens ?? 0
                let cacheRead = usage.cacheReadInputTokens ?? 0
                let total = input + output + cacheCreate + cacheRead

                guard let date = msgDate else { continue }

                if date >= startOfMonth {
                    activity.monthTokens += total
                }
                if date >= startOfWeek {
                    activity.weekTokens += total
                }
                if date >= startOfToday {
                    activity.todayTokens += total
                    activity.todayInputTokens += input
                    activity.todayOutputTokens += output
                    activity.todayCacheCreationTokens += cacheCreate
                    activity.todayCacheReadTokens += cacheRead
                }
            }
        }

        activity.currentModel = latestModel
        return activity
    }

    // MARK: - Timer

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case keychainNotFound
    case invalidToken
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .keychainNotFound:
            return "Claude Code credentials not found in Keychain. Make sure you're logged in to Claude Code."
        case .invalidToken:
            return "Could not parse OAuth token from Keychain."
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}
