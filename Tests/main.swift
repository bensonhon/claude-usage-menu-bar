import Foundation
import Combine

// Regression check: every @Published change on UsageService must be published
// on the main thread, because SwiftUI rebuilds the menu bar in response. The
// first change is `loadState = .loading` at the top of refresh(), before any
// keychain or network access, so the check exits right there.
//
// Run with Tests/check-main-thread.sh.

var cancellable: AnyCancellable?

Task { @MainActor in
    let service = UsageService()
    cancellable = service.objectWillChange.sink { _ in
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
