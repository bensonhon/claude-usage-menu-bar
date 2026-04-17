import SwiftUI

struct UsageRingView: View {
    let remaining: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let label: String?
    let resetTime: String?
    var darkMode: Bool = true

    @State private var animatedValue: Double = 0

    private var labelColor: Color {
        darkMode ? Color(hex: "CCCCCC") : Color(hex: "444444")
    }
    private var mutedColor: Color {
        darkMode ? Color(hex: "999999") : Color(hex: "666666")
    }
    private var trackColor: Color {
        darkMode ? Color.white.opacity(0.1) : Color(hex: "DDDDDD")
    }

    init(
        remaining: Double,
        size: CGFloat = 100,
        lineWidth: CGFloat = 10,
        label: String? = nil,
        resetTime: String? = nil,
        darkMode: Bool = true
    ) {
        self.remaining = remaining
        self.size = size
        self.lineWidth = lineWidth
        self.label = label
        self.resetTime = resetTime
        self.darkMode = darkMode
    }

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
        VStack(spacing: 8) {
            ZStack {
                // Background track
                Circle()
                    .stroke(
                        trackColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)

                // Foreground arc
                Circle()
                    .trim(from: 0, to: animatedValue / 100)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.4), radius: lineWidth / 2)

                // Center text
                VStack(spacing: 1) {
                    Text("\(Int(remaining))%")
                        .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                        .foregroundColor(ringColor)
                    Text("left")
                        .font(.system(size: size * 0.11, weight: .medium))
                        .foregroundColor(mutedColor)
                }
            }

            VStack(spacing: 2) {
                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(labelColor)
                }

                if let resetTime {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text("Reset by \(resetTime)")
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundColor(mutedColor)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedValue = remaining
            }
        }
        .onChange(of: remaining) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedValue = newValue
            }
        }
    }
}

// MARK: - Compact Progress Bar

struct UsageProgressBar: View {
    let label: String
    let utilization: Double
    let remaining: Double
    let resetTime: String
    var darkMode: Bool = true

    private var labelColor: Color {
        darkMode ? Color(hex: "CCCCCC") : Color(hex: "444444")
    }
    private var mutedColor: Color {
        darkMode ? Color(hex: "999999") : Color(hex: "666666")
    }
    private var trackBgColor: Color {
        darkMode ? Color.white.opacity(0.1) : Color(hex: "DDDDDD")
    }
    private var cardBgColor: Color {
        darkMode ? Color(hex: "222244") : Color(hex: "E8E8EC")
    }

    private var barColor: Color {
        if remaining > 30 {
            return Color(hex: "22C55E")
        } else if remaining > 10 {
            return Color(hex: "F59E0B")
        } else {
            return Color(hex: "EF4444")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(labelColor)
                Spacer()
                Text("\(Int(remaining))% left")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(barColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(trackBgColor)
                        .frame(height: 6)

                    // Fill (show remaining)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(remaining / 100), height: 6)
                        .shadow(color: barColor.opacity(0.3), radius: 2)
                }
            }
            .frame(height: 6)

            if resetTime != "—" {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text("Reset by \(resetTime)")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(mutedColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBgColor)
        )
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
