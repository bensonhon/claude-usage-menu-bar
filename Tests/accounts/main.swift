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

check(ClaudeAccount.keychainServiceName(configFolderPath: "/Users/benson.hon/.claude", homeFolderPath: homeFolderPath)
        == "Claude Code-credentials",
      "default config folder uses the unsuffixed Keychain entry")
check(ClaudeAccount.keychainServiceName(configFolderPath: "/Users/benson.hon/.claude2", homeFolderPath: homeFolderPath)
        == "Claude Code-credentials-e07034d5",
      "other config folder appends the first 8 hex chars of SHA-256 of its path")
check(ClaudeAccount.keychainServiceName(configFolderPath: "/Users/benson.hon/.claude", homeFolderPath: "/Users/someone-else")
        != "Claude Code-credentials",
      "a .claude folder outside the home folder is not the default")

check(ClaudeAccount.normalizedConfigFolderPath(typedPath: "  ~/.claude2/ ", homeFolderPath: homeFolderPath)
        == "/Users/benson.hon/.claude2",
      "typed path expands ~ and drops whitespace and trailing slash")
check(ClaudeAccount.normalizedConfigFolderPath(typedPath: "~", homeFolderPath: homeFolderPath) == homeFolderPath,
      "typed ~ is the home folder")
check(ClaudeAccount.normalizedConfigFolderPath(typedPath: "/opt/claude//", homeFolderPath: homeFolderPath) == "/opt/claude",
      "absolute typed path keeps its location")
check(ClaudeAccount.normalizedConfigFolderPath(typedPath: "/", homeFolderPath: homeFolderPath) == "/",
      "root path keeps its slash")

check(ClaudeAccount.isConfigFolderName(".claude2"), ".claude2 is a config folder name")
check(ClaudeAccount.isConfigFolderName(".claude-work"), ".claude-work is a config folder name")
check(!ClaudeAccount.isConfigFolderName(".config"), ".config is not a config folder name")
check(!ClaudeAccount.isConfigFolderName("claude"), "claude without the dot is not a config folder name")

check(ClaudeAccount.defaultLabel(configFolderPath: "/Users/benson.hon/.claude2") == "claude2",
      "default label is the folder name without its leading dot")
check(ClaudeAccount.defaultLabel(configFolderPath: "/opt/work") == "work",
      "default label keeps a folder name with no leading dot")

check(ClaudeAccount.displayPath(configFolderPath: "/Users/benson.hon/.claude2", homeFolderPath: homeFolderPath) == "~/.claude2",
      "display path shortens the home folder to ~")
check(ClaudeAccount.displayPath(configFolderPath: "/Users/benson.hon2/.claude", homeFolderPath: homeFolderPath) == "/Users/benson.hon2/.claude",
      "display path does not shorten a sibling folder that shares the home prefix")

let accountWithEmptyLabel = ClaudeAccount(configFolderPath: "/Users/benson.hon/.claude2", label: "  ",
                                          isShownInMenuBar: true, isFoundAutomatically: true)
check(accountWithEmptyLabel.labelOrFolderName == "claude2", "empty label falls back to the folder name")

let twoRingsImage = MenuBarIconRenderer.renderFull(
    accountRings: [
        MenuBarAccountRing(remaining: 72, resetTime: nil, accountColor: .blue),
        MenuBarAccountRing(remaining: 15, resetTime: nil, accountColor: .purple),
    ],
    showLogo: false
)
check(twoRingsImage.size.width == 22 + 6 + 22, "two rings sit 6pt apart in the menu bar")

let twoRingsWithLogoImage = MenuBarIconRenderer.renderFull(
    accountRings: [
        MenuBarAccountRing(remaining: 72, resetTime: nil, accountColor: nil),
        MenuBarAccountRing(remaining: nil, resetTime: nil, accountColor: nil),
    ],
    showLogo: true
)
check(twoRingsWithLogoImage.size.width == 16 + 4 + 22 + 6 + 22, "logo sits 4pt before the first ring")

let noRingsImage = MenuBarIconRenderer.renderFull(accountRings: [], showLogo: false)
check(noRingsImage.size.width == 16, "with no account shown the logo is still drawn so the menu bar item stays clickable")

let oneRingImage = MenuBarIconRenderer.renderFull(
    accountRings: [MenuBarAccountRing(remaining: 50, resetTime: "—", accountColor: nil)],
    showLogo: false
)
check(oneRingImage.size.width == 22, "a reset time of — is not drawn")

let ringsWithTimes = [
    MenuBarAccountRing(remaining: 72, resetTime: "4PM", accountColor: .blue),
    MenuBarAccountRing(remaining: 15, resetTime: nil, accountColor: .purple),
    MenuBarAccountRing(remaining: 40, resetTime: "7PM", accountColor: .green),
]
let firstAccountWidth = 22 + 4 + ("4PM" as NSString).size(withAttributes: [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
]).width
func clickedAccountIndex(atX x: CGFloat, showLogo: Bool) -> Int? {
    MenuBarIconRenderer.accountIndex(atX: x, accountRings: ringsWithTimes, showLogo: showLogo)
}
check(clickedAccountIndex(atX: 5, showLogo: false) == 0, "a click on the first ring picks the first account")
check(clickedAccountIndex(atX: 21.5, showLogo: false) == 0, "the first ring reaches its right edge")
check(clickedAccountIndex(atX: 22 + 4 + 2, showLogo: false) == 0, "a click on an account's reset time picks that account")
check(clickedAccountIndex(atX: firstAccountWidth + 3, showLogo: false) == nil, "a click in the gap between accounts picks nothing")
check(clickedAccountIndex(atX: firstAccountWidth + 6 + 10, showLogo: false) == 1, "a click on the second ring picks the second account")
check(clickedAccountIndex(atX: firstAccountWidth + 6 + 22 + 6 + 10, showLogo: false) == 2, "a click on the third ring picks the third account")
check(clickedAccountIndex(atX: 500, showLogo: false) == nil, "a click past the last account picks nothing")
check(clickedAccountIndex(atX: -1, showLogo: false) == nil, "a click left of the image picks nothing")
check(clickedAccountIndex(atX: 8, showLogo: true) == nil, "a click on the logo picks nothing")
check(clickedAccountIndex(atX: 16 + 4 + 10, showLogo: true) == 0, "with the logo shown the first ring starts after it")
check(MenuBarIconRenderer.accountIndex(atX: 5, accountRings: [], showLogo: true) == nil, "with no account shown a click picks nothing")

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

    accountStore.addFoundConfigFolders([secondConfigFolderPath])
    accountStore.addFoundConfigFolders([secondConfigFolderPath])
    check(accountStore.accounts.map(\.configFolderPath) == [defaultConfigFolderPath, secondConfigFolderPath],
          "a found config folder is added once")
    check(accountStore.accounts.last?.isShownInMenuBar == true, "a found config folder is shown")
    check(accountStore.accounts.last?.isFoundAutomatically == true, "a found config folder is marked found automatically")
    check(accountStore.accounts.last?.label == "claude2", "a found config folder is labelled by its folder name")
    check(accountStore.accounts.last.map(accountStore.isRemovable) == false, "a found config folder cannot be removed")

    accountStore.setShownInMenuBar(false, configFolderPath: secondConfigFolderPath)
    accountStore.addFoundConfigFolders([secondConfigFolderPath])
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

    let savedWithoutDefault = [ClaudeAccount(configFolderPath: secondConfigFolderPath, label: "second",
                                             isShownInMenuBar: true, isFoundAutomatically: true)]
    check(AccountStore.accountsIncludingDefault(savedWithoutDefault, homeFolderPath: homeFolderPath).map(\.configFolderPath)
            == [defaultConfigFolderPath, secondConfigFolderPath],
          "the default account is put first when the saved list lacks it")

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

    UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuiteName)
    print(failedCheckNames.isEmpty ? "ALL PASSED" : "FAILED: \(failedCheckNames.count)")
    exit(failedCheckNames.isEmpty ? 0 : 1)
}

RunLoop.main.run()
