import SwiftUI

struct MenuBarIconView: View {
    let remaining: Double

    private var ringColor: Color {
        if remaining > 30 {
            return Color(hex: "22C55E")
        } else if remaining > 10 {
            return Color(hex: "F59E0B")
        } else {
            return Color(hex: "EF4444")
        }
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
                .frame(width: 14, height: 14)

            // Progress arc
            Circle()
                .trim(from: 0, to: remaining / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(-90))

            // Inner dot
            Circle()
                .fill(ringColor)
                .frame(width: 4, height: 4)
        }
        .frame(width: 22, height: 22)
    }
}
