import Foundation
import AppKit

var failedCheckNames: [String] = []

func check(_ isPassing: Bool, _ checkName: String) {
    print(isPassing ? "PASS" : "FAIL", checkName)
    if !isPassing {
        failedCheckNames.append(checkName)
    }
}

let homeFolderPath = "/Users/benson.hon"

check(Account.keychainServiceName(configFolderPath: "/Users/benson.hon/.claude", homeFolderPath: homeFolderPath)
        == "Claude Code-credentials",
      "default config folder uses the unsuffixed Keychain entry")
check(Account.keychainServiceName(configFolderPath: "/Users/benson.hon/.claude2", homeFolderPath: homeFolderPath)
        == "Claude Code-credentials-e07034d5",
      "other config folder appends the first 8 hex chars of SHA-256 of its path")
check(Account.keychainServiceName(configFolderPath: "/Users/benson.hon/.claude", homeFolderPath: "/Users/someone-else")
        != "Claude Code-credentials",
      "a .claude folder outside the home folder is not the default")

check(Account.normalizedConfigFolderPath(typedPath: "  ~/.claude2/ ", homeFolderPath: homeFolderPath)
        == "/Users/benson.hon/.claude2",
      "typed path expands ~ and drops whitespace and trailing slash")
check(Account.normalizedConfigFolderPath(typedPath: "~", homeFolderPath: homeFolderPath) == homeFolderPath,
      "typed ~ is the home folder")
check(Account.normalizedConfigFolderPath(typedPath: "/opt/claude//", homeFolderPath: homeFolderPath) == "/opt/claude",
      "absolute typed path keeps its location")
check(Account.normalizedConfigFolderPath(typedPath: "/", homeFolderPath: homeFolderPath) == "/",
      "root path keeps its slash")

check(Account.isClaudeConfigFolderName(".claude2"), ".claude2 is a Claude config folder name")
check(Account.isClaudeConfigFolderName(".claude-work"), ".claude-work is a Claude config folder name")
check(!Account.isClaudeConfigFolderName(".config"), ".config is not a Claude config folder name")
check(!Account.isClaudeConfigFolderName("claude"), "claude without the dot is not a Claude config folder name")
check(!Account.isClaudeConfigFolderName(".codex"), ".codex is not a Claude config folder name")

check(Account.isCodexConfigFolderName(".codex"), ".codex is a Codex config folder name")
check(Account.isCodexConfigFolderName(".codex-work"), ".codex-work is a Codex config folder name")
check(!Account.isCodexConfigFolderName("codex"), "codex without the dot is not a Codex config folder name")
check(!Account.isCodexConfigFolderName(".claude"), ".claude is not a Codex config folder name")
check(Account.defaultLabel(configFolderPath: "/Users/benson.hon/.codex") == "codex",
      "a Codex config folder is labelled codex")

check(Account.defaultLabel(configFolderPath: "/Users/benson.hon/.claude2") == "claude2",
      "default label is the folder name without its leading dot")
check(Account.defaultLabel(configFolderPath: "/opt/work") == "work",
      "default label keeps a folder name with no leading dot")

check(Account.displayPath(configFolderPath: "/Users/benson.hon/.claude2", homeFolderPath: homeFolderPath) == "~/.claude2",
      "display path shortens the home folder to ~")
check(Account.displayPath(configFolderPath: "/Users/benson.hon2/.claude", homeFolderPath: homeFolderPath) == "/Users/benson.hon2/.claude",
      "display path does not shorten a sibling folder that shares the home prefix")

let accountWithEmptyLabel = Account(configFolderPath: "/Users/benson.hon/.claude2", label: "  ",
                                    isShownInMenuBar: true, isFoundAutomatically: true, codingTool: .claudeCode)
check(accountWithEmptyLabel.labelOrFolderName == "claude2", "empty label falls back to the folder name")

let accountSavedBeforeCodingTool = Data("""
[{"configFolderPath":"/Users/benson.hon/.claude2","label":"work","isShownInMenuBar":false,"isFoundAutomatically":true}]
""".utf8)
let decodedAccountsSavedBeforeCodingTool = try? JSONDecoder().decode([Account].self, from: accountSavedBeforeCodingTool)
check(decodedAccountsSavedBeforeCodingTool == [Account(configFolderPath: "/Users/benson.hon/.claude2", label: "work",
                                                       isShownInMenuBar: false, isFoundAutomatically: true,
                                                       codingTool: .claudeCode)],
      "an account saved before Codex support loads back as a Claude Code account")

let codexAccount = Account(configFolderPath: "/Users/benson.hon/.codex", label: "codex",
                           isShownInMenuBar: true, isFoundAutomatically: true, codingTool: .codex)
let codexAccountRoundTrip = (try? JSONEncoder().encode([codexAccount])).flatMap { try? JSONDecoder().decode([Account].self, from: $0) }
check(codexAccountRoundTrip == [codexAccount], "a Codex account is saved and loaded back as a Codex account")

let twoRingsImage = MenuBarIconRenderer.renderFull(
    accountRings: [
        MenuBarAccountRing(remaining: 72, resetDay: nil, resetTime: nil, accountColor: .blue),
        MenuBarAccountRing(remaining: 15, resetDay: nil, resetTime: nil, accountColor: .purple),
    ]
)
check(twoRingsImage.size.width == 22 + 6 + 22, "two rings sit 6pt apart in the menu bar with no logo before them")

let noRingsImage = MenuBarIconRenderer.renderFull(accountRings: [])
check(noRingsImage.size.width == 16, "with no account shown the logo is still drawn so the menu bar item stays clickable")

let oneRingImage = MenuBarIconRenderer.renderFull(
    accountRings: [MenuBarAccountRing(remaining: 50, resetDay: nil, resetTime: "—", accountColor: nil)]
)
check(oneRingImage.size.width == 22, "a reset time of — is not drawn")

let ringsWithTimes = [
    MenuBarAccountRing(remaining: 72, resetDay: nil, resetTime: "4PM", accountColor: .blue),
    MenuBarAccountRing(remaining: 15, resetDay: nil, resetTime: nil, accountColor: .purple),
    MenuBarAccountRing(remaining: 40, resetDay: nil, resetTime: "7PM", accountColor: .green),
]
let firstAccountWidth = 22 + 4 + ("4PM" as NSString).size(withAttributes: [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
]).width
func clickedAccountIndex(atX x: CGFloat) -> Int? {
    MenuBarIconRenderer.accountIndex(atX: x, accountRings: ringsWithTimes)
}
check(clickedAccountIndex(atX: 5) == 0, "a click on the first ring picks the first account")
check(clickedAccountIndex(atX: 21.5) == 0, "the first ring reaches its right edge")
check(clickedAccountIndex(atX: 22 + 4 + 2) == 0, "a click on an account's reset time picks that account")
check(clickedAccountIndex(atX: firstAccountWidth + 3) == nil, "a click in the gap between accounts picks nothing")
check(clickedAccountIndex(atX: firstAccountWidth + 6 + 10) == 1, "a click on the second ring picks the second account")
check(clickedAccountIndex(atX: firstAccountWidth + 6 + 22 + 6 + 10) == 2, "a click on the third ring picks the third account")
check(clickedAccountIndex(atX: 500) == nil, "a click past the last account picks nothing")
check(clickedAccountIndex(atX: -1) == nil, "a click left of the image picks nothing")
check(MenuBarIconRenderer.accountIndex(atX: 5, accountRings: []) == nil, "with no account shown a click on the logo picks nothing")

let weeklyRing = MenuBarAccountRing(remaining: 52, resetDay: "Thu", resetTime: "9AM", accountColor: nil)
check(MenuBarIconRenderer.timeLines(of: weeklyRing) == ["Thu", "9AM"], "a ring with a reset day shows the day on top and the time below")
check(MenuBarIconRenderer.timeLines(of: MenuBarAccountRing(remaining: 52, resetDay: nil, resetTime: "9AM", accountColor: nil)) == ["9AM"],
      "a ring without a reset day shows the time on one line")
check(MenuBarIconRenderer.timeLines(of: MenuBarAccountRing(remaining: 52, resetDay: "Thu", resetTime: nil, accountColor: nil)).isEmpty,
      "with reset time hidden the reset day is hidden too")
let twoLineTimeWidth = ["Thu", "9AM"].map { ($0 as NSString).size(withAttributes: [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
]).width }.max()!
check(MenuBarIconRenderer.renderFull(accountRings: [weeklyRing]).size.width == 22 + 4 + twoLineTimeWidth,
      "the reset day and time take the width of the wider line")

Task { @MainActor in
    let testDefaultsSuiteName = "ClaudeUsageMenuBar.AccountChecks"
    UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuiteName)
    let testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!

    let defaultConfigFolderPath = "/Users/benson.hon/.claude"
    let secondConfigFolderPath = "/Users/benson.hon/.claude2"
    let existingFolderPaths: Set<String> = ["/opt/claude-work"]
    let isExistingFolder: (String) -> Bool = { existingFolderPaths.contains($0) }

    let accountStore = AccountStore(userDefaults: testDefaults, homeFolderPath: homeFolderPath)
    check(accountStore.accounts.map(\.configFolderPath) == [defaultConfigFolderPath],
          "a new store holds only the default config folder")
    check(accountStore.accounts.first?.isShownInMenuBar == true, "the default account is shown")
    check(accountStore.accounts.first.map(accountStore.isRemovable) == false, "the default account cannot be removed")

    accountStore.addFoundConfigFolders([secondConfigFolderPath], codingTool: .claudeCode)
    accountStore.addFoundConfigFolders([secondConfigFolderPath], codingTool: .claudeCode)
    check(accountStore.accounts.map(\.configFolderPath) == [defaultConfigFolderPath, secondConfigFolderPath],
          "a found config folder is added once")
    check(accountStore.accounts.last?.isShownInMenuBar == true, "a found config folder is shown")
    check(accountStore.accounts.last?.isFoundAutomatically == true, "a found config folder is marked found automatically")
    check(accountStore.accounts.last?.label == "claude2", "a found config folder is labelled by its folder name")
    check(accountStore.accounts.last.map(accountStore.isRemovable) == false, "a found config folder cannot be removed")
    check(accountStore.accounts.last?.codingTool == .claudeCode, "a found Claude config folder is a Claude Code account")

    accountStore.setShownInMenuBar(false, configFolderPath: secondConfigFolderPath)
    accountStore.addFoundConfigFolders([secondConfigFolderPath], codingTool: .claudeCode)
    check(accountStore.shownAccounts.map(\.configFolderPath) == [defaultConfigFolderPath],
          "a hidden found config folder stays hidden when it is found again")

    @MainActor func addConfigFolderError(typedPath: String) -> AddConfigFolderError? {
        do {
            try accountStore.addConfigFolder(typedPath: typedPath, label: "", isExistingFolder: isExistingFolder)
            return nil
        } catch let error as AddConfigFolderError {
            return error
        } catch {
            preconditionFailure("unexpected error \(error)")
        }
    }
    check(addConfigFolderError(typedPath: "claude-work") == .pathNotAbsolute, "a relative path is rejected")
    check(addConfigFolderError(typedPath: "/opt/missing") == .folderNotFound, "a missing folder is rejected")
    check(addConfigFolderError(typedPath: "~/.claude2/") == .alreadyAdded, "a folder already in the list is rejected")
    check(addConfigFolderError(typedPath: "/opt/claude-work") == nil, "an existing folder is added")
    check(accountStore.accounts.last?.label == "claude-work", "an added folder with no label is labelled by its folder name")
    check(accountStore.accounts.last?.isFoundAutomatically == false, "an added folder is not marked found automatically")
    check(accountStore.accounts.last?.codingTool == .claudeCode, "an added folder is a Claude Code account")

    accountStore.setLabel("work", configFolderPath: "/opt/claude-work")
    check(accountStore.accounts.last?.label == "work", "a label can be changed")

    accountStore.moveUp(configFolderPath: "/opt/claude-work")
    check(accountStore.accounts.map(\.configFolderPath) == [defaultConfigFolderPath, "/opt/claude-work", secondConfigFolderPath],
          "move up swaps with the account above")
    accountStore.moveUp(configFolderPath: defaultConfigFolderPath)
    check(accountStore.accounts.first?.configFolderPath == defaultConfigFolderPath, "move up on the first account does nothing")
    accountStore.moveDown(configFolderPath: secondConfigFolderPath)
    check(accountStore.accounts.last?.configFolderPath == secondConfigFolderPath, "move down on the last account does nothing")

    let reloadedAccountStore = AccountStore(userDefaults: testDefaults, homeFolderPath: homeFolderPath)
    check(reloadedAccountStore.accounts == accountStore.accounts, "accounts are saved and loaded back in order")

    accountStore.remove(configFolderPath: "/opt/claude-work")
    accountStore.remove(configFolderPath: secondConfigFolderPath)
    accountStore.remove(configFolderPath: defaultConfigFolderPath)
    check(accountStore.accounts.map(\.configFolderPath) == [defaultConfigFolderPath, secondConfigFolderPath],
          "remove deletes only an added folder")

    let savedWithoutDefault = [Account(configFolderPath: secondConfigFolderPath, label: "second",
                                       isShownInMenuBar: true, isFoundAutomatically: true, codingTool: .claudeCode)]
    check(AccountStore.accountsIncludingDefault(savedWithoutDefault, homeFolderPath: homeFolderPath).map(\.configFolderPath)
            == [defaultConfigFolderPath, secondConfigFolderPath],
          "the default account is put first when the saved list lacks it")

    let codexConfigFolderPath = "/Users/benson.hon/.codex"
    accountStore.addFoundConfigFolders([codexConfigFolderPath], codingTool: .codex)
    accountStore.addFoundConfigFolders([codexConfigFolderPath], codingTool: .codex)
    check(accountStore.accounts.filter { $0.configFolderPath == codexConfigFolderPath }.count == 1,
          "a found Codex config folder is added once")
    check(accountStore.accounts.last?.codingTool == .codex, "a found Codex config folder is a Codex account")
    check(accountStore.accounts.last?.label == "codex", "a found Codex config folder is labelled codex")
    check(accountStore.accounts.last?.isShownInMenuBar == true, "a found Codex config folder is shown")
    check(AccountStore(userDefaults: testDefaults, homeFolderPath: homeFolderPath).accounts.last?.codingTool == .codex,
          "a found Codex account is saved and loaded back as a Codex account")

    let settings = AppSettings(userDefaults: testDefaults)
    check(settings.multiAccountSimpleMode == false, "simple mode is off by default")
    settings.multiAccountSimpleMode = true
    check(AppSettings(userDefaults: testDefaults).multiAccountSimpleMode == true,
          "simple mode is saved and loaded back")
    settings.multiAccountSimpleMode = false
    check(AppSettings(userDefaults: testDefaults).multiAccountSimpleMode == false,
          "simple mode can be turned off again")

    check(PopoverAccountContent.choose(multiAccountSimpleMode: false, shownAccountCount: 1) == .standard,
          "mode off with one account shows the standard popover")
    check(PopoverAccountContent.choose(multiAccountSimpleMode: false, shownAccountCount: 3) == .standard,
          "mode off with several accounts keeps the tabs")
    check(PopoverAccountContent.choose(multiAccountSimpleMode: true, shownAccountCount: 1) == .standard,
          "mode on with one account shows the standard popover")
    check(PopoverAccountContent.choose(multiAccountSimpleMode: true, shownAccountCount: 0) == .standard,
          "mode on with no account shown shows the standard popover")
    check(PopoverAccountContent.choose(multiAccountSimpleMode: true, shownAccountCount: 2) == .simpleList,
          "mode on with several accounts shows the simple list")

    check(SimpleModeWindow.allCases == [.session, .weekly],
          "simple mode switch lists Session first and Weekly second")
    check(SimpleModeWindow.allCases.map(\.title) == ["Session", "Weekly"],
          "simple mode switch titles are Session and Weekly")

    UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuiteName)
    print(failedCheckNames.isEmpty ? "ALL PASSED" : "FAILED: \(failedCheckNames.count)")
    exit(failedCheckNames.isEmpty ? 0 : 1)
}

RunLoop.main.run()
