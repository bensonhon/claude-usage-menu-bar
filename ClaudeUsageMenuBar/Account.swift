import Foundation
import CryptoKit

enum CodingTool: String, Codable {
    case claudeCode
    case codex

    var name: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

struct Account: Codable, Identifiable, Equatable {
    var configFolderPath: String
    var label: String
    var isShownInMenuBar: Bool
    var isFoundAutomatically: Bool
    var codingTool: CodingTool

    var id: String { configFolderPath }

    var labelOrFolderName: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.isEmpty ? Self.defaultLabel(configFolderPath: configFolderPath) : trimmedLabel
    }

    var projectsFolderURL: URL {
        URL(fileURLWithPath: configFolderPath).appendingPathComponent("projects")
    }

    var keychainServiceName: String {
        Self.keychainServiceName(configFolderPath: configFolderPath, homeFolderPath: Self.currentHomeFolderPath)
    }

    var displayPath: String {
        Self.displayPath(configFolderPath: configFolderPath, homeFolderPath: Self.currentHomeFolderPath)
    }

    var isDefaultConfigFolder: Bool {
        configFolderPath == Self.defaultConfigFolderPath(homeFolderPath: Self.currentHomeFolderPath)
    }
}

extension Account {
    private enum CodingKeys: String, CodingKey {
        case configFolderPath
        case label
        case isShownInMenuBar
        case isFoundAutomatically
        case codingTool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configFolderPath = try container.decode(String.self, forKey: .configFolderPath)
        label = try container.decode(String.self, forKey: .label)
        isShownInMenuBar = try container.decode(Bool.self, forKey: .isShownInMenuBar)
        isFoundAutomatically = try container.decode(Bool.self, forKey: .isFoundAutomatically)
        codingTool = try container.decodeIfPresent(CodingTool.self, forKey: .codingTool) ?? .claudeCode
    }
}

extension Account {
    static let defaultKeychainServiceName = "Claude Code-credentials"
    static let claudeConfigFolderNamePrefix = ".claude"
    static let codexConfigFolderNamePrefix = ".codex"

    static var currentHomeFolderPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    static func defaultConfigFolderPath(homeFolderPath: String) -> String {
        (homeFolderPath as NSString).appendingPathComponent(claudeConfigFolderNamePrefix)
    }

    static func keychainServiceName(configFolderPath: String, homeFolderPath: String) -> String {
        if configFolderPath == defaultConfigFolderPath(homeFolderPath: homeFolderPath) {
            return defaultKeychainServiceName
        }
        let pathBytes = Data(configFolderPath.precomposedStringWithCanonicalMapping.utf8)
        let pathHashHex = SHA256.hash(data: pathBytes).map { String(format: "%02x", $0) }.joined()
        return "\(defaultKeychainServiceName)-\(pathHashHex.prefix(8))"
    }

    static func normalizedConfigFolderPath(typedPath: String, homeFolderPath: String) -> String {
        var path = typedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "~" {
            path = homeFolderPath
        } else if path.hasPrefix("~/") {
            path = homeFolderPath + path.dropFirst()
        }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func isClaudeConfigFolderName(_ folderName: String) -> Bool {
        folderName.hasPrefix(claudeConfigFolderNamePrefix)
    }

    static func isCodexConfigFolderName(_ folderName: String) -> Bool {
        folderName.hasPrefix(codexConfigFolderNamePrefix)
    }

    static func defaultLabel(configFolderPath: String) -> String {
        let folderName = (configFolderPath as NSString).lastPathComponent
        return folderName.hasPrefix(".") ? String(folderName.dropFirst()) : folderName
    }

    static func displayPath(configFolderPath: String, homeFolderPath: String) -> String {
        if configFolderPath == homeFolderPath {
            return "~"
        }
        if configFolderPath.hasPrefix(homeFolderPath + "/") {
            return "~" + configFolderPath.dropFirst(homeFolderPath.count)
        }
        return configFolderPath
    }
}
