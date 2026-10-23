import Foundation
import CryptoKit

struct ClaudeAccount: Codable, Identifiable, Equatable {
    var configFolderPath: String
    var label: String
    var isShownInMenuBar: Bool
    var isFoundAutomatically: Bool

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

extension ClaudeAccount {
    static let defaultKeychainServiceName = "Claude Code-credentials"
    static let configFolderNamePrefix = ".claude"

    static var currentHomeFolderPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    static func defaultConfigFolderPath(homeFolderPath: String) -> String {
        (homeFolderPath as NSString).appendingPathComponent(configFolderNamePrefix)
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

    static func isConfigFolderName(_ folderName: String) -> Bool {
        folderName.hasPrefix(configFolderNamePrefix)
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
