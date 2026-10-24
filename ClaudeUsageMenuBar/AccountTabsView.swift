import SwiftUI
import AppKit

enum AccountColor {
    static let hexes = ["60A5FA", "C084FC", "F9A8D4", "67E8F9", "FDBA74", "BEF264"]

    static func hex(position: Int) -> String {
        hexes[position % hexes.count]
    }

    static func color(position: Int) -> Color {
        Color(hex: hex(position: position))
    }

    static func nsColor(position: Int) -> NSColor {
        NSColor(color(position: position))
    }
}

struct AccountTab: Identifiable {
    let configFolderPath: String
    let label: String
    let color: Color
    let sessionRemaining: Double?
    let weeklyRemaining: Double?

    var id: String { configFolderPath }

    var remainingTooltip: String {
        "Session \(AccountTab.percentText(sessionRemaining)) left · Weekly \(AccountTab.percentText(weeklyRemaining)) left"
    }

    static func percentText(_ remaining: Double?) -> String {
        remaining.map { "\(Int($0))%" } ?? "?"
    }
}

enum AccountTabRemainingLayout {
    case sessionSlashWeekly
    case sessionAboveWeekly
}

struct EqualWidthHStack: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let totalSpacing = spacing * CGFloat(subviews.count - 1)
        let widestIdealWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widestIdealWidth * CGFloat(subviews.count) + totalSpacing
        let subviewWidth = (width - totalSpacing) / CGFloat(subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: subviewWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let totalSpacing = spacing * CGFloat(subviews.count - 1)
        let subviewWidth = (bounds.width - totalSpacing) / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (subviewWidth + spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(width: subviewWidth, height: bounds.height))
        }
    }
}

struct AccountTabsView: View {
    let tabs: [AccountTab]
    let selectedConfigFolderPath: String?
    let darkMode: Bool
    let onSelect: (String) -> Void

    @State private var hoveredConfigFolderPath: String?

    private var segmentBackground: Color {
        darkMode ? Color(hex: "333355") : Color(hex: "D0D0D5")
    }
    private var selectedBackground: Color {
        darkMode ? Color(hex: "1A1A2E") : Color(hex: "F5F5F7")
    }
    private var textPrimary: Color {
        darkMode ? .white : Color(hex: "1A1A1A")
    }
    private var textMuted: Color {
        darkMode ? Color(hex: "999999") : Color(hex: "666666")
    }

    var body: some View {
        if tabs.count <= 2 {
            ViewThatFits(in: .horizontal) {
                tabBar(remainingLayout: .sessionSlashWeekly)
                tabBar(remainingLayout: .sessionAboveWeekly)
            }
        } else {
            tabBar(remainingLayout: .sessionAboveWeekly)
        }
    }

    private func tabBar(remainingLayout: AccountTabRemainingLayout) -> some View {
        EqualWidthHStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabButton(tab, remainingLayout: remainingLayout)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(segmentBackground)
        )
    }

    private func tabButton(_ tab: AccountTab, remainingLayout: AccountTabRemainingLayout) -> some View {
        let isSelected = tab.configFolderPath == selectedConfigFolderPath
        let isHovered = tab.configFolderPath == hoveredConfigFolderPath
        return Button {
            onSelect(tab.configFolderPath)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tab.color)
                    .frame(width: 7, height: 7)
                Text(tab.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? textPrimary : textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                remainingView(tab, remainingLayout: remainingLayout)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? selectedBackground : (isHovered ? selectedBackground.opacity(0.4) : .clear))
                    .shadow(color: .black.opacity(isSelected ? 0.2 : 0), radius: 1.5, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.remainingTooltip)
        .onHover { isHovering in
            hoveredConfigFolderPath = isHovering ? tab.configFolderPath : nil
        }
    }

    @ViewBuilder
    private func remainingView(_ tab: AccountTab, remainingLayout: AccountTabRemainingLayout) -> some View {
        switch remainingLayout {
        case .sessionSlashWeekly:
            HStack(spacing: 0) {
                remainingText(tab.sessionRemaining, fontSize: 11)
                Text(" / ")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(textMuted.opacity(0.6))
                remainingText(tab.weeklyRemaining, fontSize: 11)
            }
        case .sessionAboveWeekly:
            VStack(alignment: .leading, spacing: -1) {
                remainingText(tab.sessionRemaining, fontSize: 11)
                remainingText(tab.weeklyRemaining, fontSize: 9)
            }
        }
    }

    private func remainingText(_ remaining: Double?, fontSize: CGFloat) -> some View {
        Text(AccountTab.percentText(remaining))
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(remainingColor(remaining))
    }

    private func remainingColor(_ remaining: Double?) -> Color {
        guard let remaining else { return textMuted }
        if remaining > 30 {
            return Color(hex: "22C55E")
        } else if remaining > 10 {
            return Color(hex: "F59E0B")
        } else {
            return Color(hex: "EF4444")
        }
    }
}
