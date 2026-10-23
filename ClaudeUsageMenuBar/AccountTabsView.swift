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

    var id: String { configFolderPath }
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
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(segmentBackground)
        )
    }

    private func tabButton(_ tab: AccountTab) -> some View {
        let isSelected = tab.configFolderPath == selectedConfigFolderPath
        let isHovered = tab.configFolderPath == hoveredConfigFolderPath
        return Button {
            onSelect(tab.configFolderPath)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tab.color)
                    .frame(width: 7, height: 7)
                Text(tab.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? textPrimary : textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(tab.sessionRemaining.map { "\(Int($0))%" } ?? "?")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(sessionColor(tab.sessionRemaining))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? selectedBackground : (isHovered ? selectedBackground.opacity(0.4) : .clear))
                    .shadow(color: .black.opacity(isSelected ? 0.2 : 0), radius: 1.5, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredConfigFolderPath = isHovering ? tab.configFolderPath : nil
        }
    }

    private func sessionColor(_ remaining: Double?) -> Color {
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
