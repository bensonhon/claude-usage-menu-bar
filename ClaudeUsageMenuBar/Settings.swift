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

    init() {
        // Default to true for both
        if UserDefaults.standard.object(forKey: "showLogo") == nil {
            UserDefaults.standard.set(true, forKey: "showLogo")
        }
        if UserDefaults.standard.object(forKey: "showResetTime") == nil {
            UserDefaults.standard.set(true, forKey: "showResetTime")
        }
        self.showLogo = UserDefaults.standard.bool(forKey: "showLogo")
        self.showResetTime = UserDefaults.standard.bool(forKey: "showResetTime")
    }
}
