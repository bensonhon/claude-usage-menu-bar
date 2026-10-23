import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var settings: AppSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var refreshHovered = false
    @State private var quitHovered = false

    private let popoverWidth: CGFloat = 300

    /// Measured height of the popover's content. The MenuBarExtra window adopts
    /// whatever definite size we give its root view. A ScrollView has no
    /// intrinsic height, so without an explicit height the window collapses to a
    /// tiny sliver on macOS versions that honor the degenerate fitting size
    /// (seen on macOS 26). We measure the content and size the window to it.
    @State private var contentHeight: CGFloat = 420

    /// Cap the popover to most of the screen height so tall content scrolls
    /// instead of running past the screen edge.
    private var maxPopoverHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        return visibleHeight * 0.85
    }

    private var bgColor: Color {
        settings.darkMode ? Color(hex: "1A1A2E") : Color(hex: "F5F5F7")
    }
    private var cardColor: Color {
        settings.darkMode ? Color(hex: "222244") : Color(hex: "E8E8EC")
    }
    private var textPrimary: Color {
        settings.darkMode ? .white : Color(hex: "1A1A1A")
    }
    private var textSecondary: Color {
        settings.darkMode ? Color(hex: "CCCCCC") : Color(hex: "444444")
    }
    private var textMuted: Color {
        settings.darkMode ? Color(hex: "999999") : Color(hex: "666666")
    }

    private var shownAccounts: [ClaudeAccount] {
        accountStore.shownAccounts
    }

    private var selectedAccount: ClaudeAccount? {
        shownAccounts.first { $0.configFolderPath == settings.selectedConfigFolderPath } ?? shownAccounts.first
    }

    private var selectedUsage: AccountUsage {
        selectedAccount.map(service.usage(for:)) ?? AccountUsage()
    }

    private var isAccountColorShown: Bool {
        shownAccounts.count > 1
    }

    private var accountContent: PopoverAccountContent {
        PopoverAccountContent.choose(
            multiAccountSimpleMode: settings.multiAccountSimpleMode,
            shownAccountCount: shownAccounts.count
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                headerSection
                switch accountContent {
                case .simpleList:
                    simpleAccountList
                case .standard:
                    if isAccountColorShown {
                        AccountTabsView(
                            tabs: accountTabs,
                            selectedConfigFolderPath: selectedAccount?.configFolderPath,
                            darkMode: settings.darkMode,
                            onSelect: selectAccount
                        )
                    }
                    if let selectedAccount {
                        selectedAccountSection(selectedAccount)
                            .id(selectedAccount.configFolderPath)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        noAccountShownSection
                    }
                }
                settingsSection
                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
        .frame(width: popoverWidth, height: min(max(contentHeight, 360), maxPopoverHeight))
        .background(bgColor)
        .onPreferenceChange(ContentHeightPreferenceKey.self) { newHeight in
            if newHeight > 0 {
                contentHeight = newHeight
            }
        }
        .task {
            await service.refresh()
        }
    }

    // MARK: - Header

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return v.isEmpty ? "" : "v\(v)"
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Claude Usage")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(textPrimary)
            Text(appVersion)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textMuted)
            Spacer()
        }
    }

    private var accountTabs: [AccountTab] {
        shownAccounts.map { account in
            AccountTab(
                configFolderPath: account.configFolderPath,
                label: account.labelOrFolderName,
                color: AccountColor.color(position: accountStore.position(of: account)),
                sessionRemaining: service.usage(for: account).sessionWindow?.remaining
            )
        }
    }

    private func selectAccount(_ configFolderPath: String) {
        if reduceMotion {
            settings.selectedConfigFolderPath = configFolderPath
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                settings.selectedConfigFolderPath = configFolderPath
            }
        }
    }

    private func selectedAccountSection(_ account: ClaudeAccount) -> some View {
        let usage = service.usage(for: account)
        return VStack(spacing: 8) {
            accountCard(account, usage: usage)
            loginProblemNote(usage.keychainLoginStatus)
            secondarySection(usage)
            extraUsageSection(usage)
            RecentSessionsView(
                sessions: usage.tokenActivity.recentSessions,
                isLoading: !usage.tokenActivityLoaded,
                darkMode: settings.darkMode
            )
            TokenHistoryView(
                activity: usage.tokenActivity,
                isLoading: !usage.tokenActivityLoaded,
                darkMode: settings.darkMode
            )
        }
    }

    // MARK: - Simple Account List

    /// Weekly rings side by side, one column per shown account in Settings
    /// order, with any login problems listed under the rings.
    private var simpleAccountList: some View {
        let ringSize: CGFloat = shownAccounts.count > 3 ? 48 : (shownAccounts.count > 2 ? 58 : 70)
        let isCompact = shownAccounts.count > 2
        return VStack(spacing: 8) {
            HStack {
                Text("Weekly (7d)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textMuted)
                Spacer()
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(shownAccounts) { account in
                    simpleAccountColumn(account, usage: service.usage(for: account), ringSize: ringSize, isCompact: isCompact)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardColor)
            )
            ForEach(shownAccounts) { account in
                loginProblemNote(
                    service.usage(for: account).keychainLoginStatus,
                    accountLabel: account.labelOrFolderName,
                    dotColor: AccountColor.color(position: accountStore.position(of: account))
                )
            }
        }
    }

    private func simpleAccountColumn(_ account: ClaudeAccount, usage: AccountUsage, ringSize: CGFloat, isCompact: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(AccountColor.color(position: accountStore.position(of: account)))
                    .frame(width: 7, height: 7)
                Text(account.labelOrFolderName)
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .foregroundColor(textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 2)
            UsageRingView(
                remaining: usage.weeklyWindow?.remaining,
                size: ringSize,
                lineWidth: ringSize > 60 ? 7 : 6,
                label: nil,
                resetTime: usage.weeklyWindow?.resetClockString,
                darkMode: settings.darkMode,
                compactReset: isCompact
            )
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
    }

    private var noAccountShownSection: some View {
        Text("No accounts shown. Turn one on under Accounts.")
            .font(.system(size: 12))
            .foregroundColor(textMuted)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardColor)
            )
    }

    // MARK: - Main Rings

    private func accountCard(_ account: ClaudeAccount, usage: AccountUsage) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                if isAccountColorShown {
                    Circle()
                        .fill(AccountColor.color(position: accountStore.position(of: account)))
                        .frame(width: 7, height: 7)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.labelOrFolderName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)
                    Text(account.displayPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(usage.hasUsageData ? usage.planName : "—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(usage.hasUsageData ? Color(hex: "E8732A") : textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((usage.hasUsageData ? Color(hex: "E8732A") : textMuted).opacity(0.15))
                    )
            }
            .padding(.horizontal, 4)
            mainRingsSection(usage)
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardColor)
        )
    }

    @ViewBuilder
    private func loginProblemNote(
        _ keychainLoginStatus: KeychainLoginStatus,
        accountLabel: String? = nil,
        dotColor: Color? = nil
    ) -> some View {
        switch keychainLoginStatus {
        case .tokenExpired:
            loginProblemText("Login token expired. Use Claude Code with this account once, and it comes back on the next refresh.", accountLabel: accountLabel, dotColor: dotColor)
        case .notFound:
            loginProblemText("No Claude Code login found for this folder. Sign in to Claude Code with this config folder.", accountLabel: accountLabel, dotColor: dotColor)
        case .unreadable:
            loginProblemText("Could not read this account's login from Keychain.", accountLabel: accountLabel, dotColor: dotColor)
        case .notChecked, .found:
            EmptyView()
        }
    }

    /// `accountLabel` and `dotColor` name the account when several notes share
    /// one list; the single-account views leave them off.
    private func loginProblemText(_ text: String, accountLabel: String?, dotColor: Color?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
            Text(accountLabel.map { "\($0): \(text)" } ?? text)
        }
        .font(.system(size: 11))
        .foregroundColor(textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "F59E0B").opacity(0.14))
        )
    }

    private func mainRingsSection(_ usage: AccountUsage) -> some View {
        HStack(spacing: 20) {
            UsageRingView(
                remaining: usage.sessionWindow?.remaining,
                size: 70,
                lineWidth: 7,
                label: "Session (5h)",
                resetTime: usage.sessionWindow?.resetClockString,
                darkMode: settings.darkMode
            )
            .frame(maxWidth: .infinity)

            UsageRingView(
                remaining: usage.weeklyWindow?.remaining,
                size: 70,
                lineWidth: 7,
                label: "Weekly (7d)",
                resetTime: usage.weeklyWindow?.resetClockString,
                darkMode: settings.darkMode
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Secondary Windows

    @ViewBuilder
    private func secondarySection(_ usage: AccountUsage) -> some View {
        let items = usage.secondaryWindows
        if !items.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "E8732A").opacity(0.8))
                    Text("Model Usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textPrimary)
                    Spacer()
                }

                ForEach(items) { item in
                    UsageProgressBar(
                        label: item.label,
                        utilization: item.utilization,
                        remaining: item.remaining,
                        resetTime: item.resetTime,
                        darkMode: settings.darkMode
                    )
                }
            }
        }
    }

    // MARK: - Extra Usage

    @ViewBuilder
    private func extraUsageSection(_ usage: AccountUsage) -> some View {
        if let extra = usage.extraUsage, extra.isEnabled {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "F59E0B"))
                    Text("Extra Usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textPrimary)
                    Spacer()
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Credits Used")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(textMuted)
                        Text(String(format: "$%.2f", (extra.usedCredits ?? 0) / 100))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    if let limit = extra.monthlyLimit {
                        Text("/")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(textMuted)
                            .padding(.horizontal, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly Limit")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(textMuted)
                            Text(String(format: "$%.2f", limit / 100))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if let limit = extra.monthlyLimit, limit > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cardColor)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "F59E0B"))
                                .frame(
                                    width: geo.size.width * CGFloat(min((extra.usedCredits ?? 0) / limit, 1.0)),
                                    height: 6
                                )
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardColor)
            )
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundColor(textMuted)
                Text("Menu Bar Options")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textPrimary)
                Spacer()
            }

            Toggle(isOn: $settings.showLogo) {
                Text("Show Claude logo")
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $settings.showResetTime) {
                Text("Show reset time")
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
            }
            .toggleStyle(.checkbox)

            Divider()
                .background(cardColor)

            AccountListView(accountStore: accountStore, service: service, darkMode: settings.darkMode)

            Toggle(isOn: $settings.multiAccountSimpleMode) {
                Text("Multiple account simple mode")
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
            }
            .toggleStyle(.checkbox)

            Divider()
                .background(cardColor)

            HStack {
                Text("Appearance")
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundColor(settings.darkMode ? .white : textMuted)
                        .frame(width: 34, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.darkMode ? Color(hex: "E8732A") : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { settings.darkMode = true }

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10))
                        .foregroundColor(!settings.darkMode ? .white : textMuted)
                        .frame(width: 34, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(!settings.darkMode ? Color(hex: "E8732A") : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { settings.darkMode = false }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(settings.darkMode ? Color(hex: "333355") : Color(hex: "D0D0D5"))
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardColor)
        )
    }

    // MARK: - Footer

    private func friendlyErrorMessage(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("keychain") || lower.contains("token") || lower.contains("401") {
            return "Requires Claude Code CLI. Sign in via `claude` to load usage data."
        }
        return raw
    }

    /// In the simple list no account is selected, so show the freshest refresh.
    private var footerLastUpdated: Date? {
        switch accountContent {
        case .simpleList:
            return shownAccounts.compactMap { service.usage(for: $0).lastUpdated }.max()
        case .standard:
            return selectedUsage.lastUpdated
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Divider()
                .background(cardColor)

            HStack {
                if let lastUpdated = footerLastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundColor(textMuted)
                }

                Spacer()

                Button {
                    Task { await service.refresh(force: true) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text("Refresh")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "E8732A"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "E8732A").opacity(refreshHovered ? 0.18 : 0))
                    )
                }
                .buttonStyle(.plain)
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        refreshHovered = true
                        NSCursor.pointingHand.set()
                    case .ended:
                        refreshHovered = false
                        NSCursor.arrow.set()
                    }
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .medium))
                        Text("Quit")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "EF4444"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "EF4444").opacity(quitHovered ? 0.18 : 0))
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        quitHovered = true
                        NSCursor.pointingHand.set()
                    case .ended:
                        quitHovered = false
                        NSCursor.arrow.set()
                    }
                }
            }

            HStack {
                Spacer()
                Link(destination: URL(string: "https://claude.ai")!) {
                    HStack(spacing: 3) {
                        Text("Open claude.ai")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundColor(textMuted)
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }

            if accountContent == .standard,
               case .error(let msg) = selectedUsage.loadState, !selectedUsage.keychainLoginStatus.isLoginProblem {
                Text(friendlyErrorMessage(msg))
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Carries the popover's measured content height up to the frame modifier so the
/// MenuBarExtra window can be sized to a definite height instead of collapsing.
private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
