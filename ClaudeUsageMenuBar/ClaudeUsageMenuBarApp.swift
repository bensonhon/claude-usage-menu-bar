import SwiftUI
import AppKit
import ServiceManagement

@main
struct ClaudeUsageMenuBarApp: App {
    @StateObject private var accountStore: AccountStore
    @StateObject private var service: UsageService
    @StateObject private var settings = AppSettings()

    init() {
        Self.terminateOtherInstances()
        // Auto-register as login item so the app starts on boot
        try? SMAppService.mainApp.register()
        let accountStore = AccountStore()
        _accountStore = StateObject(wrappedValue: accountStore)
        _service = StateObject(wrappedValue: UsageService(accountStore: accountStore))
    }

    /// Terminate any other running copies of this app so an upgrade-then-launch
    /// doesn't leave the previous version sitting in the menu bar.
    private static func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app != me && app.processIdentifier != me.processIdentifier {
            if !app.terminate() {
                app.forceTerminate()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(service: service, accountStore: accountStore, settings: settings)
        } label: {
            Image(nsImage: MenuBarIconRenderer.renderFull(
                accountRings: menuBarAccountRings,
                showLogo: settings.showLogo
            ))
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarAccountRings: [MenuBarAccountRing] {
        let shownAccounts = accountStore.shownAccounts
        let isAccountColorShown = shownAccounts.count > 1
        return shownAccounts.map { account in
            let sessionWindow = service.usage(for: account).sessionWindow
            return MenuBarAccountRing(
                remaining: sessionWindow?.remaining,
                resetTime: settings.showResetTime ? sessionWindow?.resetClockShort : nil,
                accountColor: isAccountColorShown ? AccountColor.nsColor(position: accountStore.position(of: account)) : nil
            )
        }
    }
}
