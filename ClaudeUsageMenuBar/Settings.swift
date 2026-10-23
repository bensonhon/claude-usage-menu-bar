import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    @Published var showLogo: Bool {
        didSet { userDefaults.set(showLogo, forKey: "showLogo") }
    }
    @Published var showResetTime: Bool {
        didSet { userDefaults.set(showResetTime, forKey: "showResetTime") }
    }
    @Published var darkMode: Bool {
        didSet { userDefaults.set(darkMode, forKey: "darkMode") }
    }
    @Published var selectedConfigFolderPath: String? {
        didSet { userDefaults.set(selectedConfigFolderPath, forKey: "selectedConfigFolderPath") }
    }
    @Published var multiAccountSimpleMode: Bool {
        didSet { userDefaults.set(multiAccountSimpleMode, forKey: "multiAccountSimpleMode") }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: "showLogo") == nil {
            userDefaults.set(true, forKey: "showLogo")
        }
        if userDefaults.object(forKey: "showResetTime") == nil {
            userDefaults.set(true, forKey: "showResetTime")
        }
        if userDefaults.object(forKey: "darkMode") == nil {
            userDefaults.set(true, forKey: "darkMode")
        }
        self.showLogo = userDefaults.bool(forKey: "showLogo")
        self.showResetTime = userDefaults.bool(forKey: "showResetTime")
        self.darkMode = userDefaults.bool(forKey: "darkMode")
        self.selectedConfigFolderPath = userDefaults.string(forKey: "selectedConfigFolderPath")
        self.multiAccountSimpleMode = userDefaults.bool(forKey: "multiAccountSimpleMode")
    }
}

/// Which account content the popover shows above its settings and footer.
enum PopoverAccountContent: Equatable {
    /// Account tabs, or the single account's full detail.
    case standard
    /// One compact weekly-usage block per shown account, no tabs.
    case simpleList

    static func choose(multiAccountSimpleMode: Bool, shownAccountCount: Int) -> PopoverAccountContent {
        multiAccountSimpleMode && shownAccountCount > 1 ? .simpleList : .standard
    }
}
