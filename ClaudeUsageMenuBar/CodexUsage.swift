import Foundation

struct CodexLoginToken: Equatable {
    let accessToken: String
    let chatGPTAccountID: String
}

enum CodexAuthFile {
    static let fileName = "auth.json"

    static func path(configFolderPath: String) -> String {
        (configFolderPath as NSString).appendingPathComponent(fileName)
    }

    static func exists(configFolderPath: String) -> Bool {
        FileManager.default.fileExists(atPath: path(configFolderPath: configFolderPath))
    }

    static func readLoginToken(configFolderPath: String, now: Date) throws -> CodexLoginToken {
        let authFileData: Data
        do {
            authFileData = try Data(contentsOf: URL(fileURLWithPath: path(configFolderPath: configFolderPath)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw UsageError.loginNotFound(.codex)
        } catch {
            throw UsageError.invalidToken(.codex)
        }
        return try loginToken(authFileData: authFileData, now: now)
    }

    static func loginToken(authFileData: Data, now: Date) throws -> CodexLoginToken {
        guard let authFile = (try? JSONSerialization.jsonObject(with: authFileData)) as? [String: Any] else {
            throw UsageError.invalidToken(.codex)
        }
        guard let tokens = authFile["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty,
              let chatGPTAccountID = tokens["account_id"] as? String, !chatGPTAccountID.isEmpty else {
            throw UsageError.loginNotFound(.codex)
        }
        guard let accessTokenExpiryDate = accessTokenExpiryDate(accessToken: accessToken) else {
            throw UsageError.invalidToken(.codex)
        }
        if accessTokenExpiryDate < now {
            throw UsageError.tokenExpired(.codex)
        }
        return CodexLoginToken(accessToken: accessToken, chatGPTAccountID: chatGPTAccountID)
    }

    static func accessTokenExpiryDate(accessToken: String) -> Date? {
        let tokenParts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard tokenParts.count == 3 else { return nil }
        var claimsBase64 = String(tokenParts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        claimsBase64 += String(repeating: "=", count: (4 - claimsBase64.count % 4) % 4)
        guard let claimsData = Data(base64Encoded: claimsBase64),
              let claims = (try? JSONSerialization.jsonObject(with: claimsData)) as? [String: Any],
              let expirySeconds = claims["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: expirySeconds)
    }
}

struct CodexUsageResponse {
    var windows: [String: UsageWindow] = [:]
    var planName: String

    static func decode(from data: Data) throws -> CodexUsageResponse {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.networkError("Invalid JSON response")
        }
        guard let planType = raw["plan_type"] as? String else {
            throw UsageError.networkError("Codex usage reply has no plan_type")
        }
        guard let rateLimit = raw["rate_limit"] as? [String: Any] else {
            throw UsageError.networkError("Codex usage reply has no rate_limit")
        }
        var response = CodexUsageResponse(planName: planName(planType: planType))
        for rateLimitWindowName in ["primary_window", "secondary_window"] {
            guard let rateLimitWindow = rateLimit[rateLimitWindowName] as? [String: Any] else { continue }
            guard let usedPercent = rateLimitWindow["used_percent"] as? Double,
                  let limitWindowSeconds = rateLimitWindow["limit_window_seconds"] as? Int else {
                throw UsageError.networkError("Codex usage reply has a \(rateLimitWindowName) without used_percent or limit_window_seconds")
            }
            let resetDate = (rateLimitWindow["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            response.windows[windowKey(limitWindowSeconds: limitWindowSeconds)] = UsageWindow(
                utilization: usedPercent,
                resetDate: resetDate
            )
        }
        return response
    }

    static func windowKey(limitWindowSeconds: Int) -> String {
        switch limitWindowSeconds {
        case 5 * 60 * 60:
            return "five_hour"
        case 7 * 24 * 60 * 60:
            return "seven_day"
        default:
            return "\(limitWindowSeconds / 3600)_hour"
        }
    }

    static let selfServePlanTypePrefix = "self_serve_"

    static func planName(planType: String) -> String {
        let planTypeWithoutSelfServe = planType.hasPrefix(selfServePlanTypePrefix)
            ? String(planType.dropFirst(selfServePlanTypePrefix.count))
            : planType
        return planTypeWithoutSelfServe
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
