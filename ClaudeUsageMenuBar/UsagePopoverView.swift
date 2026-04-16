import SwiftUI

struct UsagePopoverView: View {
    let service: UsageService

    private let popoverWidth: CGFloat = 340
    private let bgColor = Color(hex: "1A1A2E")
    private let cardColor = Color(hex: "16213E")

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    headerSection
                    mainRingsSection
                    secondarySection
                    extraUsageSection
                    TokenHistoryView(activity: service.tokenActivity)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude Usage")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(service.planName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "E8732A"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: "E8732A").opacity(0.15))
                    )
            }

            if let model = service.tokenActivity.currentModel {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(modelColor(model))
                    Text("Current Model")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(formatModelName(model))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(modelColor(model))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(modelColor(model).opacity(0.1))
                )
            }
        }
    }

    private func formatModelName(_ raw: String) -> String {
        // "claude-opus-4-6" → "Opus 4.6"
        // "claude-sonnet-4-6" → "Sonnet 4.6"
        let parts = raw.replacingOccurrences(of: "claude-", with: "")
            .components(separatedBy: "-")
        guard parts.count >= 3 else { return raw }
        let name = parts[0].capitalized
        let version = parts[1...].joined(separator: ".")
        return "\(name) \(version)"
    }

    private func modelColor(_ raw: String) -> Color {
        if raw.contains("opus") {
            return Color(hex: "C084FC")  // purple
        } else if raw.contains("sonnet") {
            return Color(hex: "60A5FA")  // blue
        } else if raw.contains("haiku") {
            return Color(hex: "34D399")  // green
        }
        return Color(hex: "E8732A")
    }

    // MARK: - Main Rings

    private var mainRingsSection: some View {
        HStack(spacing: 20) {
            if let session = service.sessionWindow {
                UsageRingView(
                    remaining: session.remaining,
                    size: 70,
                    lineWidth: 7,
                    label: "Session (5h)",
                    resetTime: session.resetClockString
                )
                .frame(maxWidth: .infinity)
            }

            if let weekly = service.weeklyWindow {
                UsageRingView(
                    remaining: weekly.remaining,
                    size: 70,
                    lineWidth: 7,
                    label: "Weekly (7d)",
                    resetTime: weekly.resetClockString
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
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
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }

                ForEach(items) { item in
                    UsageProgressBar(
                        label: item.label,
                        utilization: item.utilization,
                        remaining: item.remaining,
                        resetTime: item.resetTime
                    )
                }
            }
        }
    }

    // MARK: - Extra Usage

    @ViewBuilder
    private var extraUsageSection: some View {
        if let extra = service.extraUsage, extra.isEnabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "F59E0B"))
                    Text("Extra Usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Credits Used")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(String(format: "$%.2f", extra.usedCredits ?? 0))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    if let limit = extra.monthlyLimit {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Monthly Limit")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(String(format: "$%.2f", limit))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }

                if let limit = extra.monthlyLimit, limit > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.white.opacity(0.1))

            HStack {
                if let lastUpdated = service.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task { await service.refresh() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text("Refresh")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "E8732A"))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
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
                    .foregroundColor(.secondary)
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
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "EF4444"))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
