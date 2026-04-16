import SwiftUI

struct TokenHistoryView: View {
    let activity: TokenActivity
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
                tokenCard(title: "Today", value: activity.todayTokens)
                Spacer()
                tokenCard(title: "This Week", value: activity.weekTokens)
                Spacer()
                tokenCard(title: "This Month", value: activity.monthTokens)
            }

            // Today's breakdown
            if activity.todayTokens > 0 {
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
