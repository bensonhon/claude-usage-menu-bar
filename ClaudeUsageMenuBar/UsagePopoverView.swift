import SwiftUI

struct UsagePopoverView: View {
    let service: UsageService
    var settings: AppSettings

    @State private var refreshHovered = false
    @State private var quitHovered = false

    private let popoverWidth: CGFloat = 300

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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    headerSection
                    mainRingsSection
                    secondarySection
                    extraUsageSection
                    RecentSessionsView(
                        sessions: service.tokenActivity.recentSessions,
                        isLoading: !service.tokenActivityLoaded,
                        darkMode: settings.darkMode
                    )
                    TokenHistoryView(
                        activity: service.tokenActivity,
                        isLoading: !service.tokenActivityLoaded,
                        darkMode: settings.darkMode
                    )
                    settingsSection
                    footerSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
        .frame(width: popoverWidth)
        .frame(maxHeight: 1000)
        .background(bgColor)
        .task {
            await service.refresh()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Claude Usage")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(textPrimary)
            Spacer()
            Text(service.hasUsageData ? service.planName : "—")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(service.hasUsageData ? Color(hex: "E8732A") : textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((service.hasUsageData ? Color(hex: "E8732A") : textMuted).opacity(0.15))
                )
        }
    }

    // MARK: - Main Rings

    private var mainRingsSection: some View {
        HStack(spacing: 20) {
            UsageRingView(
                remaining: service.sessionWindow?.remaining,
                size: 70,
                lineWidth: 7,
                label: "Session (5h)",
                resetTime: service.sessionWindow?.resetClockString,
                darkMode: settings.darkMode
            )
            .frame(maxWidth: .infinity)

            UsageRingView(
                remaining: service.weeklyWindow?.remaining,
                size: 70,
                lineWidth: 7,
                label: "Weekly (7d)",
                resetTime: service.weeklyWindow?.resetClockString,
                darkMode: settings.darkMode
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardColor)
        )
    }

    // MARK: - Secondary Windows

    @ViewBuilder
    private var secondarySection: some View {
        let items = service.secondaryWindows
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
    private var extraUsageSection: some View {
        if let extra = service.extraUsage, extra.isEnabled {
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

            Toggle(isOn: Bindable(settings).showLogo) {
                Text("Show Claude logo")
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Bindable(settings).showResetTime) {
                Text("Show reset time")
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

    private var footerSection: some View {
        VStack(spacing: 8) {
            Divider()
                .background(cardColor)

            HStack {
                if let lastUpdated = service.lastUpdated {
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

            if case .error(let msg) = service.loadState {
                Text(friendlyErrorMessage(msg))
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
