import Foundation

var failedCheckNames: [String] = []

func check(_ isPassing: Bool, _ checkName: String) {
    print(isPassing ? "PASS" : "FAIL", checkName)
    if !isPassing {
        failedCheckNames.append(checkName)
    }
}

func base64URL(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func accessToken(expirySeconds: Int) -> String {
    base64URL(#"{"alg":"RS256"}"#) + "." + base64URL(#"{"exp":\#(expirySeconds),"iat":1}"#) + ".signature"
}

func authFileData(accessToken: String, chatGPTAccountID: String = "account-1") -> Data {
    Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"x","access_token":"\#(accessToken)","refresh_token":"r","account_id":"\#(chatGPTAccountID)"}}"#.utf8)
}

func usageError(_ run: () throws -> Any) -> UsageError? {
    do {
        _ = try run()
        return nil
    } catch let error as UsageError {
        return error
    } catch {
        preconditionFailure("unexpected error \(error)")
    }
}

func isSameUsageError(_ first: UsageError?, _ second: UsageError) -> Bool {
    guard let first else { return false }
    return first.localizedDescription == second.localizedDescription
}

let now = Date(timeIntervalSince1970: 1_000_000)

check(CodexAuthFile.accessTokenExpiryDate(accessToken: accessToken(expirySeconds: 1_864_000))
        == Date(timeIntervalSince1970: 1_864_000),
      "the access token expiry is read from its exp claim")
check(CodexAuthFile.accessTokenExpiryDate(accessToken: "not-a-jwt") == nil,
      "a token that is not three dot-separated parts has no expiry")
check(CodexAuthFile.accessTokenExpiryDate(accessToken: "a." + base64URL(#"{"iat":1}"#) + ".c") == nil,
      "a token without an exp claim has no expiry")

let validLoginToken = try? CodexAuthFile.loginToken(
    authFileData: authFileData(accessToken: accessToken(expirySeconds: 1_000_001), chatGPTAccountID: "account-7"),
    now: now
)
check(validLoginToken == CodexLoginToken(accessToken: accessToken(expirySeconds: 1_000_001), chatGPTAccountID: "account-7"),
      "a ChatGPT login gives the access token and the ChatGPT account id")

check(isSameUsageError(usageError { try CodexAuthFile.loginToken(authFileData: authFileData(accessToken: accessToken(expirySeconds: 999_999)), now: now) },
                       .tokenExpired(.codex)),
      "an access token past its exp is expired")
check(usageError { try CodexAuthFile.loginToken(authFileData: authFileData(accessToken: accessToken(expirySeconds: 999_999)), now: now) }?.loginStatus
        == .tokenExpired,
      "an expired Codex token shows the token expired status")

let apiKeyAuthFileData = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-test","tokens":null}"#.utf8)
check(isSameUsageError(usageError { try CodexAuthFile.loginToken(authFileData: apiKeyAuthFileData, now: now) },
                       .loginNotFound(.codex)),
      "an API key login has no ChatGPT login")

check(isSameUsageError(usageError { try CodexAuthFile.loginToken(authFileData: Data("not json".utf8), now: now) },
                       .invalidToken(.codex)),
      "an auth.json that is not JSON is unreadable")
check(isSameUsageError(usageError { try CodexAuthFile.loginToken(authFileData: authFileData(accessToken: "opaque-token"), now: now) },
                       .invalidToken(.codex)),
      "an access token with no readable expiry is unreadable")

let missingConfigFolderPath = NSTemporaryDirectory() + "codex-usage-checks-\(UUID().uuidString)"
check(isSameUsageError(usageError { try CodexAuthFile.readLoginToken(configFolderPath: missingConfigFolderPath, now: now) },
                       .loginNotFound(.codex)),
      "a folder with no auth.json has no Codex login")

let configFolderPath = NSTemporaryDirectory() + "codex-usage-checks-\(UUID().uuidString)"
try FileManager.default.createDirectory(atPath: configFolderPath, withIntermediateDirectories: true)
check(!CodexAuthFile.exists(configFolderPath: configFolderPath), "auth.json is not found before it is written")
try authFileData(accessToken: accessToken(expirySeconds: 2_000_000)).write(to: URL(fileURLWithPath: CodexAuthFile.path(configFolderPath: configFolderPath)))
check(CodexAuthFile.exists(configFolderPath: configFolderPath), "auth.json is found once it is written")
check((try? CodexAuthFile.readLoginToken(configFolderPath: configFolderPath, now: now))?.chatGPTAccountID == "account-1",
      "the login token is read from the config folder's auth.json")
try FileManager.default.removeItem(atPath: configFolderPath)

let weeklyOnlyReply = Data("""
{"plan_type":"self_serve_business_prolite",
 "rate_limit":{"allowed":true,"limit_reached":false,
   "primary_window":{"used_percent":34,"limit_window_seconds":604800,"reset_after_seconds":515491,"reset_at":1795799695},
   "secondary_window":null},
 "credits":{"has_credits":false}}
""".utf8)
let weeklyOnlyUsage = try? CodexUsageResponse.decode(from: weeklyOnlyReply)
check(weeklyOnlyUsage?.windows.keys.sorted() == ["seven_day"], "a 7-day primary window is the weekly window")
check(weeklyOnlyUsage?.windows["seven_day"]?.utilization == 34, "used_percent is the window's utilization")
check(weeklyOnlyUsage?.windows["seven_day"]?.remaining == 66, "34% used leaves 66% remaining")
check(weeklyOnlyUsage?.windows["seven_day"]?.resetDate == Date(timeIntervalSince1970: 1_795_799_695),
      "reset_at is the window's reset time")
check(weeklyOnlyUsage?.planName == "Business Prolite", "plan_type is shown as words without the self_serve_ prefix")
check(CodexUsageResponse.planName(planType: "business_self_serve") == "Business Self Serve",
      "self_serve is only dropped from the start of plan_type")

let sessionAndWeeklyReply = Data("""
{"plan_type":"plus",
 "rate_limit":{
   "primary_window":{"used_percent":12.5,"limit_window_seconds":18000,"reset_at":1795700000},
   "secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":1795799695}}}
""".utf8)
let sessionAndWeeklyUsage = try? CodexUsageResponse.decode(from: sessionAndWeeklyReply)
check(sessionAndWeeklyUsage?.windows["five_hour"]?.utilization == 12.5, "a 5-hour primary window is the session window")
check(sessionAndWeeklyUsage?.windows["seven_day"]?.utilization == 40, "a 7-day secondary window is the weekly window")
check(sessionAndWeeklyUsage?.planName == "Plus", "a one-word plan_type is capitalized")

check(CodexUsageResponse.windowKey(limitWindowSeconds: 30 * 24 * 60 * 60) == "720_hour",
      "a window of another length is named by its length in hours")

check(usageError { try CodexUsageResponse.decode(from: Data(#"{"plan_type":"plus","rate_limit":null}"#.utf8)) } != nil,
      "a reply with no rate_limit is an error")
check(usageError { try CodexUsageResponse.decode(from: Data(#"{"rate_limit":{}}"#.utf8)) } != nil,
      "a reply with no plan_type is an error")
check(usageError { try CodexUsageResponse.decode(from: Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000}}}"#.utf8)) } != nil,
      "a window without used_percent is an error")

var weeklyOnlyAccountUsage = AccountUsage()
weeklyOnlyAccountUsage.windows = weeklyOnlyUsage?.windows ?? [:]
check(weeklyOnlyAccountUsage.menuBarRingWindow?.utilization == 34,
      "with no session window the menu bar ring shows the weekly window")

var sessionAndWeeklyAccountUsage = AccountUsage()
sessionAndWeeklyAccountUsage.windows = sessionAndWeeklyUsage?.windows ?? [:]
check(sessionAndWeeklyAccountUsage.menuBarRingWindow?.utilization == 12.5,
      "with a session window the menu bar ring shows the session window")

check(AccountUsage().menuBarRingWindow == nil, "with no windows the menu bar ring has no window")

var thursdayNineAMComponents = DateComponents()
thursdayNineAMComponents.year = 2026
thursdayNineAMComponents.month = 11
thursdayNineAMComponents.day = 26
thursdayNineAMComponents.hour = 9
thursdayNineAMComponents.minute = 10
let thursdayNineAM = Calendar.current.date(from: thursdayNineAMComponents)!
var weeklyResetOnThursdayUsage = AccountUsage()
weeklyResetOnThursdayUsage.windows = ["seven_day": UsageWindow(utilization: 48, resetDate: thursdayNineAM)]
check(weeklyResetOnThursdayUsage.menuBarRingResetDay == "Thu", "a menu bar ring showing the weekly window shows its reset day")
weeklyResetOnThursdayUsage.windows["five_hour"] = UsageWindow(utilization: 10, resetDate: thursdayNineAM)
check(weeklyResetOnThursdayUsage.menuBarRingResetDay == nil, "a menu bar ring showing the session window shows no reset day")

var thursdayLateComponents = thursdayNineAMComponents
thursdayLateComponents.hour = 23
thursdayLateComponents.minute = 45
var weeklyResetLateThursdayUsage = AccountUsage()
weeklyResetLateThursdayUsage.windows = ["seven_day": UsageWindow(utilization: 48, resetDate: Calendar.current.date(from: thursdayLateComponents)!)]
check(weeklyResetLateThursdayUsage.menuBarRingResetDay == "Fri", "the reset day follows the time rounded to the hour")

check(UsageError.tokenExpired(.codex).localizedDescription
        == "Codex login token expired. Use Codex with this account once to refresh it.",
      "the expired message names Codex")
check(UsageError.tokenExpired(.claudeCode).localizedDescription
        == "Claude Code login token expired. Use Claude Code with this account once to refresh it.",
      "the expired message for Claude is unchanged")

print(failedCheckNames.isEmpty ? "ALL PASSED" : "FAILED: \(failedCheckNames.count)")
exit(failedCheckNames.isEmpty ? 0 : 1)
