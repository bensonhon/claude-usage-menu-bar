import Foundation
import Combine

// Regression check: every @Published change on UsageService must be published
// on the main thread, because SwiftUI rebuilds the menu bar in response.
//
// Run with Tests/check-main-thread.sh.

var cancellable: AnyCancellable?
let testDefaultsSuiteName = "ClaudeUsageMenuBar.MainThreadCheck"
UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuiteName)

Task { @MainActor in
    let accountStore = AccountStore(userDefaults: UserDefaults(suiteName: testDefaultsSuiteName)!)
    let service = UsageService(accountStore: accountStore)
    cancellable = service.objectWillChange.sink { _ in
        UserDefaults.standard.removePersistentDomain(forName: testDefaultsSuiteName)
        if Thread.isMainThread {
            print("PASS: first @Published change was published on the main thread")
            exit(0)
        } else {
            print("FAIL: @Published change was published off the main thread")
            exit(1)
        }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print("FAIL: no @Published change within 10s")
    exit(2)
}
RunLoop.main.run()
