import Foundation

// MARK: - API Response (flat structure)

/// The API returns a flat JSON object where each key is a window name.
/// Values can be null. We decode manually.
struct UsageResponse {
    var windows: [String: UsageWindow] = [:]
    var extraUsage: ExtraUsage?
}

extension UsageResponse {
    static func decode(from data: Data) throws -> UsageResponse {
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.networkError("Invalid JSON response")
        }

        var response = UsageResponse()

        // Parse extra_usage separately
        if let extraDict = raw["extra_usage"] as? [String: Any] {
            response.extraUsage = ExtraUsage(
                isEnabled: extraDict["is_enabled"] as? Bool ?? false,
                usedCredits: extraDict["used_credits"] as? Double,
                monthlyLimit: extraDict["monthly_limit"] as? Double
            )
        }

        // All other keys are usage windows
        let skipKeys: Set<String> = ["extra_usage"]
        for (key, value) in raw {
            if skipKeys.contains(key) { continue }
            guard let dict = value as? [String: Any] else { continue }
            guard let utilization = dict["utilization"] as? Double else { continue }
            let resetsAt = dict["resets_at"] as? String
            response.windows[key] = UsageWindow(
                utilization: utilization,
                resetsAt: resetsAt
            )
        }

        return response
    }
}

struct UsageWindow {
    let utilization: Double
    let resetsAt: String?

    var remaining: Double {
        max(0, min(100, 100 - utilization))
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }

    /// Round to nearest hour (e.g. 2:59PM → 3PM)
    private var resetDateRounded: Date? {
        guard let date = resetDate else { return nil }
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        if minute >= 30 {
            return calendar.date(byAdding: .minute, value: 60 - minute, to: date)
        } else {
            return calendar.date(byAdding: .minute, value: -minute, to: date)
        }
    }

    private func formatHour(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.amSymbol = "AM"
        fmt.pmSymbol = "PM"
        let minute = Calendar.current.component(.minute, from: date)
        fmt.dateFormat = minute == 0 ? "ha" : "h:mma"
        return fmt.string(from: date)
    }

    /// Short time only — for menu bar icon
    var resetClockShort: String {
        guard let date = resetDateRounded else { return "—" }
        return formatHour(date)
    }

    /// Full date + time — for popover detail view
    var resetClockString: String {
        guard let date = resetDateRounded else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return formatHour(date)
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(formatHour(date))"
        } else {
            let fmt = DateFormatter()
            fmt.amSymbol = "AM"
            fmt.pmSymbol = "PM"
            fmt.dateFormat = "MMM d, ha"
            return fmt.string(from: date)
        }
    }

    var resetTimeString: String {
        guard let date = resetDate else { return "—" }
        let now = Date()
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Now" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "\(days)d \(remHours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct ExtraUsage {
    let isEnabled: Bool
    let usedCredits: Double?
    let monthlyLimit: Double?
}

// MARK: - OAuth Token

struct OAuthCredentials: Codable {
    let claudeAiOauth: OAuthToken?

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claudeAiOauth"
    }
}

struct OAuthToken: Codable {
    let accessToken: String
    let expiresAt: Double?
    let subscriptionType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "accessToken"
        case expiresAt = "expiresAt"
        case subscriptionType = "subscriptionType"
    }
}

// MARK: - Token History

struct TokenActivity {
    var todayTokens: Int = 0
    var weekTokens: Int = 0
    var monthTokens: Int = 0
    var todayInputTokens: Int = 0
    var todayOutputTokens: Int = 0
    var todayCacheCreationTokens: Int = 0
    var todayCacheReadTokens: Int = 0
    var currentModel: String? = nil
    var currentSessionFile: String? = nil
}

struct JSONLMessage: Codable {
    let type: String?
    let timestamp: String?
    let message: MessageContent?

    struct MessageContent: Codable {
        let id: String?
        let model: String?
        let usage: TokenUsage?
    }

    struct TokenUsage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}

// MARK: - Usage State

enum UsageLoadState {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - Window Display Info

struct WindowDisplayInfo: Identifiable {
    let id: String
    let label: String
    let utilization: Double
    let remaining: Double
    let resetTime: String

    init(key: String, window: UsageWindow) {
        self.id = key
        self.label = WindowDisplayInfo.labelForKey(key)
        self.utilization = window.utilization
        self.remaining = window.remaining
        self.resetTime = window.resetClockString
    }

    static func labelForKey(_ key: String) -> String {
        switch key {
        case "five_hour": return "Session (5h)"
        case "seven_day": return "Weekly (7d)"
        case "seven_day_sonnet": return "Sonnet (7d)"
        case "seven_day_opus": return "Opus (7d)"
        case "seven_day_haiku": return "Haiku (7d)"
        case "seven_day_cowork": return "Cowork (7d)"
        case "seven_day_omelette": return "Omelette (7d)"
        case "iguana_necktie": return "Priority Tier"
        case "omelette_promotional": return "Omelette Promo"
        case "seven_day_oauth_apps": return "OAuth Apps (7d)"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
