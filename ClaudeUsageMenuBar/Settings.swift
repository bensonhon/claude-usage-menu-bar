import Foundation
import SwiftUI

@Observable
final class AppSettings {
    var showLogo: Bool {
        didSet { UserDefaults.standard.set(showLogo, forKey: "showLogo") }
    }
    var showResetTime: Bool {
        didSet { UserDefaults.standard.set(showResetTime, forKey: "showResetTime") }
    }
    var darkMode: Bool {
        didSet { UserDefaults.standard.set(darkMode, forKey: "darkMode") }
    }

    init() {
        if UserDefaults.standard.object(forKey: "showLogo") == nil {
            UserDefaults.standard.set(true, forKey: "showLogo")
        }
        if UserDefaults.standard.object(forKey: "showResetTime") == nil {
            UserDefaults.standard.set(true, forKey: "showResetTime")
        }
        if UserDefaults.standard.object(forKey: "darkMode") == nil {
            UserDefaults.standard.set(true, forKey: "darkMode")
        }
        self.showLogo = UserDefaults.standard.bool(forKey: "showLogo")
        self.showResetTime = UserDefaults.standard.bool(forKey: "showResetTime")
        self.darkMode = UserDefaults.standard.bool(forKey: "darkMode")
    }
}
