import SwiftUI
import AppKit

/// Compact card listing recent Claude Code sessions. Shows up to 3 rows at a time.
/// When idle, auto-advances one row every ~2s with a visible linear scroll. When
/// hovered, auto-advance pauses and the user can scroll freely. The scrollbar is
/// always visible (via a legacy-style NSScrollView) so hovering never shifts layout.
struct RecentSessionsView: View {
    let sessions: [SessionSummary]
    let isLoading: Bool
    let darkMode: Bool

    private let visibleRows = 3
    private let rowHeight: CGFloat = 22
    private let rowSpacing: CGFloat = 1
    private let advanceInterval: TimeInterval = 2.0
    private let scrollDuration: TimeInterval = 0.5
    private let nameMaxChars = 22
    private let activeWindow: TimeInterval = 5 * 60

    @State private var topIndex: Int = 0
    @State private var timer: Timer?
    @State private var isHovering = false
    @State private var now = Date()
    @State private var tickTimer: Timer?

    private var cardColor: Color {
        darkMode ? Color(hex: "222244") : Color(hex: "DDE0E7")
    }
    private var rowBg: Color {
        darkMode ? Color(hex: "2E2E5C") : Color(hex: "F4F6FA")
    }
    private var textPrimary: Color {
        darkMode ? .white : Color(hex: "1A1A1A")
    }
    private var textMuted: Color {
        darkMode ? Color(hex: "999999") : Color(hex: "666666")
    }

    private var shouldAutoScroll: Bool { sessions.count > visibleRows }

    private var viewportHeight: CGFloat {
        let rows = isLoading ? visibleRows : min(sessions.count, visibleRows)
        return CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "E8732A").opacity(0.8))
                Text("Recent Sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textPrimary)
                Spacer()
                if isLoading {
                    Text("…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(textMuted)
                } else {
                    Text("\(sessions.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if isLoading {
                VStack(spacing: rowSpacing) {
                    ForEach(0..<visibleRows, id: \.self) { _ in
                        skeletonRow
                            .frame(height: rowHeight)
                    }
                }
                .frame(height: viewportHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else if sessions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity)
                    .frame(height: viewportHeight)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                LegacyScrollView(
                    topIndex: topIndex,
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    scrollDuration: scrollDuration
                ) {
                    VStack(spacing: rowSpacing) {
                        ForEach(sessions) { session in
                            row(for: session)
                                .frame(height: rowHeight)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 0)
                }
                .frame(height: viewportHeight)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardColor)
        )
        .onAppear { startTimers() }
        .onDisappear {
            timer?.invalidate()
            tickTimer?.invalidate()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func startTimers() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            now = Date()
        }

        guard shouldAutoScroll else { return }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: advanceInterval, repeats: true) { _ in
            guard !isHovering else { return }
            advance()
        }
    }

    private func advance() {
        let maxTop = max(sessions.count - visibleRows, 0)
        if topIndex >= maxTop {
            topIndex = 0
        } else {
            topIndex += 1
        }
    }

    // MARK: - Row

    private func row(for session: SessionSummary) -> some View {
        let isActive = now.timeIntervalSince(session.lastActivity) < activeWindow
        return HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color(hex: "22C55E") : Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(session.projectName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                Text(shortModel(session.model))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(modelColor(session.model))
                    .frame(width: 40, alignment: .trailing)

                Text(relativeTime(session.lastActivity))
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
                    .frame(width: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBg)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(textMuted)
            Text("No sessions in the last 10 days")
                .font(.system(size: 11))
                .foregroundColor(textMuted)
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
            SkeletonBlock(width: 120, height: 10, darkMode: darkMode)
            Spacer(minLength: 0)
            SkeletonBlock(width: 40, height: 10, darkMode: darkMode)
            SkeletonBlock(width: 32, height: 10, darkMode: darkMode)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBg)
        )
    }

    private func truncate(_ s: String, to n: Int) -> String {
        if s.count <= n { return s }
        let prefix = s.prefix(n - 1)
        return "\(prefix)…"
    }

    private func shortModel(_ raw: String) -> String {
        if raw.contains("opus") { return "Opus" }
        if raw.contains("sonnet") { return "Sonnet" }
        if raw.contains("haiku") { return "Haiku" }
        return raw
    }

    private func modelColor(_ raw: String) -> Color {
        if raw.contains("opus") { return Color(hex: "C084FC") }
        if raw.contains("sonnet") { return Color(hex: "60A5FA") }
        if raw.contains("haiku") { return Color(hex: "34D399") }
        return Color(hex: "E8732A")
    }

    private func relativeTime(_ date: Date) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "now" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        return "\(months)mo"
    }
}

// MARK: - Skeleton block

/// Small pulsing rectangle used as a loading placeholder for text.
struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let darkMode: Bool

    @State private var pulse: Bool = false

    private var baseColor: Color {
        darkMode ? Color.white.opacity(0.12) : Color.gray.opacity(0.25)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(baseColor)
            .opacity(pulse ? 0.6 : 1.0)
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Legacy-style NSScrollView wrapper

/// Wraps NSScrollView with always-visible (legacy) scrollers so the scrollbar
/// doesn't pop in/out and shift layout on hover. Supports programmatic scrolling
/// to a row index via `topIndex` with a smooth linear animation.
private struct LegacyScrollView<Content: View>: NSViewRepresentable {
    let topIndex: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let scrollDuration: TimeInterval
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .legacy  // always-visible scrollbar
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        // Pin hosting view to the clip view's width so the document resizes with the scroller.
        if let clip = scrollView.contentView as NSClipView? {
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: clip.topAnchor),
                hosting.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            ])
        }

        context.coordinator.hosting = hosting
        context.coordinator.scrollView = scrollView
        context.coordinator.lastIndex = topIndex
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let clip = nsView.contentView as NSClipView? else { return }

        // Preserve the current scroll origin across the content swap (a re-render
        // from a color / prop change) so an in-flight animation isn't clobbered.
        let savedOrigin = clip.bounds.origin
        let isContentOnly = context.coordinator.lastIndex == topIndex

        if let hosting = context.coordinator.hosting as? NSHostingView<Content> {
            hosting.rootView = content()
        }

        if isContentOnly {
            if clip.bounds.origin != savedOrigin {
                clip.setBoundsOrigin(savedOrigin)
                nsView.reflectScrolledClipView(clip)
            }
            return
        }

        context.coordinator.lastIndex = topIndex
        let target = NSPoint(x: 0, y: CGFloat(topIndex) * (rowHeight + rowSpacing))

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = scrollDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            ctx.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(target)
            nsView.reflectScrolledClipView(clip)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var hosting: NSView?
        weak var scrollView: NSScrollView?
        var lastIndex: Int = -1
    }
}
