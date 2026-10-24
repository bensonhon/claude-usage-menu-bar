import Foundation
import SwiftUI

var failedCheckNames: [String] = []

func check(_ isPassing: Bool, _ checkName: String) {
    print(isPassing ? "PASS" : "FAIL", checkName)
    if !isPassing {
        failedCheckNames.append(checkName)
    }
}

func makeTab(label: String, sessionRemaining: Double?, weeklyRemaining: Double?) -> AccountTab {
    AccountTab(configFolderPath: "/Users/benson.hon/.\(label)", label: label, color: .blue,
               sessionRemaining: sessionRemaining, weeklyRemaining: weeklyRemaining)
}

check(AccountTab.percentText(87.9) == "87%", "percent text drops the fraction")
check(AccountTab.percentText(nil) == "?", "missing percent shows ?")
check(makeTab(label: "Main", sessionRemaining: 87, weeklyRemaining: 64).remainingTooltip
        == "Session 87% left · Weekly 64% left",
      "tooltip names session and weekly percent left")
check(makeTab(label: "Main", sessionRemaining: 87, weeklyRemaining: nil).remainingTooltip
        == "Session 87% left · Weekly ? left",
      "tooltip shows ? for missing weekly percent")

let popoverTabBarWidth: CGFloat = 300 - 16 * 2

@MainActor func tabBarHeight(_ tabs: [AccountTab]) -> CGFloat {
    let renderer = ImageRenderer(content: AccountTabsView(tabs: tabs, selectedConfigFolderPath: tabs.first?.configFolderPath,
                                                          darkMode: true, onSelect: { _ in }))
    renderer.proposedSize = ProposedViewSize(width: popoverTabBarWidth, height: nil)
    return renderer.nsImage?.size.height ?? 0
}

Task { @MainActor in
    let main = makeTab(label: "Main", sessionRemaining: 87, weeklyRemaining: 64)
    let spare = makeTab(label: "Spare", sessionRemaining: 27, weeklyRemaining: 8)
    let work = makeTab(label: "Work", sessionRemaining: 100, weeklyRemaining: 41)
    let longName = makeTab(label: "benson-work-account", sessionRemaining: 100, weeklyRemaining: 100)

    let twoShortNamesHeight = tabBarHeight([main, spare])
    let twoWithLongNameHeight = tabBarHeight([main, longName])
    let threeShortNamesHeight = tabBarHeight([main, spare, work])

    check(twoShortNamesHeight > 0, "the tab bar renders")
    check(twoShortNamesHeight < threeShortNamesHeight,
          "two short names show session / weekly on one line, three accounts stack weekly below session")
    check(twoWithLongNameHeight == threeShortNamesHeight,
          "two accounts stack weekly below session when a name does not fit beside session / weekly")

    print(failedCheckNames.isEmpty ? "ALL PASSED" : "FAILED: \(failedCheckNames.count)")
    exit(failedCheckNames.isEmpty ? 0 : 1)
}

RunLoop.main.run()
