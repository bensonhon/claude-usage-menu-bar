import SwiftUI

struct TokenHistoryView: View {
    let activity: TokenActivity
    var isLoading: Bool = false
    var darkMode: Bool = true

    private var labelColor: Color {
        darkMode ? Color(hex: "CCCCCC") : Color(hex: "444444")
    }
    private var textColor: Color {
        darkMode ? .white : Color(hex: "1A1A1A")
    }
    private var cardBgColor: Color {
        darkMode ? Color(hex: "222244") : Color(hex: "E8E8EC")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "E8732A"))
                Text("Token Activity")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(labelColor)
            }

            // Summary row
            HStack(spacing: 0) {
                if isLoading {
                    skeletonCard(title: "Today")
                    Spacer()
                    skeletonCard(title: "Last 3 Days")
                    Spacer()
                    skeletonCard(title: "Last 7 Days")
                } else {
                    tokenCard(title: "Today", value: activity.todayTokens)
                    Spacer()
                    tokenCard(title: "Last 3 Days", value: activity.last3DaysTokens)
                    Spacer()
                    tokenCard(title: "Last 7 Days", value: activity.last7DaysTokens)
                }
            }

            // Today's breakdown
            if isLoading {
                VStack(spacing: 4) {
                    skeletonDetailRow(label: "Input", color: Color(hex: "60A5FA"))
                    skeletonDetailRow(label: "Output", color: Color(hex: "34D399"))
                    skeletonDetailRow(label: "Cache Write", color: Color(hex: "A78BFA"))
                    skeletonDetailRow(label: "Cache Read", color: Color(hex: "FBBF24"))
                }
                .padding(.top, 2)
            } else if activity.todayTokens > 0 {
                VStack(spacing: 4) {
                    tokenDetailRow(label: "Input", tokens: activity.todayInputTokens, color: Color(hex: "60A5FA"))
                    tokenDetailRow(label: "Output", tokens: activity.todayOutputTokens, color: Color(hex: "34D399"))
                    tokenDetailRow(label: "Cache Write", tokens: activity.todayCacheCreationTokens, color: Color(hex: "A78BFA"))
                    tokenDetailRow(label: "Cache Read", tokens: activity.todayCacheReadTokens, color: Color(hex: "FBBF24"))
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBgColor)
        )
    }

    private func tokenCard(title: String, value: Int) -> some View {
        VStack(spacing: 3) {
            Text(formatTokenCount(value))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func tokenDetailRow(label: String, tokens: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
            Spacer()
            Text(formatTokenCount(tokens))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(labelColor)
        }
        .padding(.horizontal, 12)
    }

    private func skeletonCard(title: String) -> some View {
        VStack(spacing: 4) {
            SkeletonBlock(width: 38, height: 14, darkMode: darkMode)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func skeletonDetailRow(label: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(labelColor)
            Spacer()
            SkeletonBlock(width: 36, height: 10, darkMode: darkMode)
        }
        .padding(.horizontal, 12)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
