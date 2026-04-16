import SwiftUI

struct TokenHistoryView: View {
    let activity: TokenActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "E8732A"))
                Text("Token Activity")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
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
                .fill(Color.white.opacity(0.04))
        )
    }

    private func tokenCard(title: String, value: Int) -> some View {
        VStack(spacing: 3) {
            Text(formatTokenCount(value))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
            Spacer()
            Text(formatTokenCount(tokens))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
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
