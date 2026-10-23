import Foundation
import SwiftUI

enum AddConfigFolderError: LocalizedError, Equatable {
    case pathNotAbsolute
    case folderNotFound
    case alreadyAdded

    var errorDescription: String? {
        switch self {
        case .pathNotAbsolute:
            return "Use a full path, like ~/.claude-work."
        case .folderNotFound:
            return "That folder does not exist."
        case .alreadyAdded:
            return "That folder is already in the list."
        }
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [ClaudeAccount] {
        didSet { saveAccounts() }
    }

    private static let accountsKey = "accounts"
    private let userDefaults: UserDefaults
    private let homeFolderPath: String

    init(userDefaults: UserDefaults = .standard, homeFolderPath: String = ClaudeAccount.currentHomeFolderPath) {
        self.userDefaults = userDefaults
        self.homeFolderPath = homeFolderPath
        let savedAccounts = Self.loadSavedAccounts(from: userDefaults)
        self.accounts = Self.accountsIncludingDefault(savedAccounts, homeFolderPath: homeFolderPath)
    }

    var shownAccounts: [ClaudeAccount] {
        accounts.filter(\.isShownInMenuBar)
    }

    func position(of account: ClaudeAccount) -> Int {
        accounts.firstIndex { $0.configFolderPath == account.configFolderPath } ?? 0
    }

    func addFoundConfigFolders(_ foundConfigFolderPaths: [String]) {
        let knownConfigFolderPaths = Set(accounts.map(\.configFolderPath))
        let newAccounts = foundConfigFolderPaths
            .filter { !knownConfigFolderPaths.contains($0) }
            .map {
                ClaudeAccount(
                    configFolderPath: $0,
                    label: ClaudeAccount.defaultLabel(configFolderPath: $0),
                    isShownInMenuBar: true,
                    isFoundAutomatically: true
                )
            }
        if !newAccounts.isEmpty {
            accounts.append(contentsOf: newAccounts)
        }
    }

    func addConfigFolder(typedPath: String, label: String, isExistingFolder: (String) -> Bool) throws {
        let configFolderPath = ClaudeAccount.normalizedConfigFolderPath(typedPath: typedPath, homeFolderPath: homeFolderPath)
        guard configFolderPath.hasPrefix("/") else {
            throw AddConfigFolderError.pathNotAbsolute
        }
        guard !accounts.contains(where: { $0.configFolderPath == configFolderPath }) else {
            throw AddConfigFolderError.alreadyAdded
        }
        guard isExistingFolder(configFolderPath) else {
            throw AddConfigFolderError.folderNotFound
        }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts.append(ClaudeAccount(
            configFolderPath: configFolderPath,
            label: trimmedLabel.isEmpty ? ClaudeAccount.defaultLabel(configFolderPath: configFolderPath) : trimmedLabel,
            isShownInMenuBar: true,
            isFoundAutomatically: false
        ))
    }

    func setShownInMenuBar(_ isShownInMenuBar: Bool, configFolderPath: String) {
        guard let index = index(of: configFolderPath) else { return }
        accounts[index].isShownInMenuBar = isShownInMenuBar
    }

    func setLabel(_ label: String, configFolderPath: String) {
        guard let index = index(of: configFolderPath) else { return }
        accounts[index].label = label
    }

    func moveUp(configFolderPath: String) {
        guard let index = index(of: configFolderPath), index > 0 else { return }
        accounts.swapAt(index, index - 1)
    }

    func moveDown(configFolderPath: String) {
        guard let index = index(of: configFolderPath), index < accounts.count - 1 else { return }
        accounts.swapAt(index, index + 1)
    }

    func isRemovable(_ account: ClaudeAccount) -> Bool {
        !account.isFoundAutomatically
            && account.configFolderPath != ClaudeAccount.defaultConfigFolderPath(homeFolderPath: homeFolderPath)
    }

    func remove(configFolderPath: String) {
        guard let index = index(of: configFolderPath), isRemovable(accounts[index]) else { return }
        accounts.remove(at: index)
    }

    private func index(of configFolderPath: String) -> Int? {
        accounts.firstIndex { $0.configFolderPath == configFolderPath }
    }

    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        userDefaults.set(data, forKey: Self.accountsKey)
    }

    private static func loadSavedAccounts(from userDefaults: UserDefaults) -> [ClaudeAccount] {
        guard let data = userDefaults.data(forKey: accountsKey) else { return [] }
        return (try? JSONDecoder().decode([ClaudeAccount].self, from: data)) ?? []
    }

    static func accountsIncludingDefault(_ savedAccounts: [ClaudeAccount], homeFolderPath: String) -> [ClaudeAccount] {
        let defaultConfigFolderPath = ClaudeAccount.defaultConfigFolderPath(homeFolderPath: homeFolderPath)
        if savedAccounts.contains(where: { $0.configFolderPath == defaultConfigFolderPath }) {
            return savedAccounts
        }
        let defaultAccount = ClaudeAccount(
            configFolderPath: defaultConfigFolderPath,
            label: ClaudeAccount.defaultLabel(configFolderPath: defaultConfigFolderPath),
            isShownInMenuBar: true,
            isFoundAutomatically: false
        )
        return [defaultAccount] + savedAccounts
    }
}
