import AppKit
import CmuxSidebar

/// DevBox: compact Claude Code usage badge drawn under a workspace row.
///
/// Layout (one line): `[ who ]  (◔ 23% 2h)  (◑ 41% 3d)` — an account chip,
/// then one capsule per rate-limit window holding a ring gauge, the used
/// share and the time until reset. Narrow sidebars drop the reset text
/// first, then the window labels. The view owns a minute timer so the
/// countdown and post-reset state stay current without a new report.
@MainActor
final class SidebarRowClaudeUsageBadgeView: NSView {
    /// Sizes already scaled by the sidebar font scale.
    struct Metrics: Equatable {
        var percentFont: CGFloat
        var smallFont: CGFloat
        var chipFont: CGFloat
        var ring: CGFloat
        var pad: CGFloat
        var inner: CGFloat
        var gap: CGFloat

        init(scaled: (CGFloat) -> CGFloat) {
            percentFont = scaled(9.5)
            smallFont = scaled(8.5)
            chipFont = scaled(9)
            ring = scaled(10)
            pad = scaled(5)
            inner = scaled(3)
            gap = scaled(5)
        }
    }

    struct Style: Equatable {
        var metrics: Metrics
        var isSelected: Bool
        var primary: NSColor
        var secondary: NSColor
        var chipFill: NSColor
        var capsuleFill: NSColor
        var track: NSColor
    }

    private struct Segment {
        let label: String
        let window: SidebarClaudeUsage.Window
    }

    private var usage: SidebarClaudeUsage?
    private var style: Style?
    private var minuteTimer: Timer?

    override var isFlipped: Bool { true }

    func configure(usage: SidebarClaudeUsage, style: Style) {
        guard self.usage != usage || self.style != style else { return }
        self.usage = usage
        self.style = style
        refreshAccessibility()
        needsDisplay = true
    }

    /// Fixed one-line height so row measurement never depends on content.
    static func height(scaledLineHeight: CGFloat) -> CGFloat {
        ceil(scaledLineHeight)
    }

    // MARK: - Timer

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        minuteTimer?.invalidate()
        minuteTimer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(minuteTick), userInfo: nil, repeats: true)
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    @objc private func minuteTick() {
        guard !isHidden, usage != nil else { return }
        refreshAccessibility()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let usage, let style else { return }
        let now = Date()
        let height = bounds.height
        let m = style.metrics
        let pctFont = NSFont.monospacedDigitSystemFont(ofSize: m.percentFont, weight: .semibold)
        let smallFont = NSFont.systemFont(ofSize: m.smallFont, weight: .medium)
        let chipFont = NSFont.systemFont(ofSize: m.chipFont, weight: .semibold)
        let ring = m.ring
        let pad = m.pad
        let inner = m.inner
        let gap = m.gap

        let segments = self.segments(for: usage)
        let chipText = usage.who
        let chipWidth = chipText.isEmpty ? 0 : textWidth(chipText, chipFont) + pad * 2

        func segmentWidth(_ segment: Segment, showLabel: Bool, showReset: Bool) -> CGFloat {
            var w = pad + ring + inner + textWidth(percentText(segment.window, now), pctFont) + pad
            if showLabel { w += textWidth(segment.label, smallFont) + inner }
            if showReset, let reset = resetText(segment.window, now) { w += inner + textWidth(reset, smallFont) }
            return w
        }
        func totalWidth(showLabel: Bool, showReset: Bool) -> CGFloat {
            var w = chipWidth
            for segment in segments {
                if w > 0 { w += gap }
                w += segmentWidth(segment, showLabel: showLabel, showReset: showReset)
            }
            return w
        }
        let tiers: [(Bool, Bool)] = [(true, true), (false, true), (false, false)]
        let (showLabel, showReset) = tiers.first { totalWidth(showLabel: $0.0, showReset: $0.1) <= bounds.width }
            ?? (false, false)

        var x: CGFloat = 0
        if chipWidth > 0 {
            let rect = NSRect(x: x, y: 0, width: chipWidth, height: height)
            style.chipFill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            drawText(chipText, font: chipFont, color: style.primary, x: x + pad, height: height)
            x += chipWidth
        }
        for segment in segments {
            if x > 0 { x += gap }
            let width = segmentWidth(segment, showLabel: showLabel, showReset: showReset)
            guard x + width <= bounds.width + 0.5 else { break }
            let rect = NSRect(x: x, y: 0, width: width, height: height)
            style.capsuleFill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            var cx = x + pad
            if showLabel {
                cx += drawText(segment.label, font: smallFont, color: style.secondary, x: cx, height: height) + inner
            }
            let percent = segment.window.effectivePercent(now: now)
            drawRing(
                in: NSRect(x: cx, y: (height - ring) / 2, width: ring, height: ring),
                fraction: CGFloat(percent) / 100,
                color: gaugeColor(percent: percent, selected: style.isSelected),
                track: style.track
            )
            cx += ring + inner
            cx += drawText(percentText(segment.window, now), font: pctFont, color: style.primary, x: cx, height: height)
            if showReset, let reset = resetText(segment.window, now) {
                cx += inner
                drawText(reset, font: smallFont, color: style.secondary, x: cx, height: height)
            }
            x += width
        }
    }

    private func drawRing(in rect: NSRect, fraction: CGFloat, color: NSColor, track: NSColor) {
        let lineWidth = max(1.5, rect.width * 0.2)
        let circleRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
        let radius = circleRect.width / 2
        let trackPath = NSBezierPath(ovalIn: circleRect)
        trackPath.lineWidth = lineWidth
        track.setStroke()
        trackPath.stroke()
        guard fraction > 0 else { return }
        // Flipped view: start at 12 o'clock and sweep clockwise on screen.
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center, radius: radius,
            startAngle: -90, endAngle: -90 + 360 * min(1, fraction), clockwise: false
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    @discardableResult
    private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, height: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)
        return ceil(size.width)
    }

    private func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func gaugeColor(percent: Int, selected: Bool) -> NSColor {
        switch (SidebarClaudeUsageLevel(percent: percent), selected) {
        case (.normal, false): return .systemGreen
        case (.elevated, false): return .systemOrange
        case (.critical, false): return .systemRed
        case (.normal, true): return .white
        case (.elevated, true): return .systemYellow
        case (.critical, true): return NSColor(srgbRed: 1, green: 0.62, blue: 0.62, alpha: 1)
        }
    }

    // MARK: - Text

    private func segments(for usage: SidebarClaudeUsage) -> [Segment] {
        var result: [Segment] = []
        if let window = usage.fiveHour {
            result.append(Segment(
                label: String(localized: "sidebar.claudeUsage.fiveHour.short", defaultValue: "5h"),
                window: window
            ))
        }
        if let window = usage.sevenDay {
            result.append(Segment(
                label: String(localized: "sidebar.claudeUsage.weekly.short", defaultValue: "7d"),
                window: window
            ))
        }
        return result
    }

    private func percentText(_ window: SidebarClaudeUsage.Window, _ now: Date) -> String {
        "\(window.effectivePercent(now: now))%"
    }

    private static let countdownFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        return formatter
    }()

    private func resetText(_ window: SidebarClaudeUsage.Window, _ now: Date) -> String? {
        guard let seconds = window.secondsUntilReset(now: now) else { return nil }
        // Round down to the shown unit, but never display "0m".
        return Self.countdownFormatter.string(from: max(60, seconds))
    }

    private func refreshAccessibility() {
        guard let usage else { return }
        let now = Date()
        var lines: [String] = []
        let who = usage.who.isEmpty ? "Claude Code" : usage.who
        lines.append(String.localizedStringWithFormat(
            String(localized: "sidebar.claudeUsage.tooltip.title", defaultValue: "Claude Code usage · %@"),
            who
        ))
        func line(_ window: SidebarClaudeUsage.Window, used: String, usedReset: String) -> String {
            let percent = window.effectivePercent(now: now)
            guard window.secondsUntilReset(now: now) != nil, let resetsAt = window.resetsAt else {
                return String.localizedStringWithFormat(used, percent)
            }
            let when = resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return String.localizedStringWithFormat(usedReset, percent, when)
        }
        if let window = usage.fiveHour {
            lines.append(line(
                window,
                used: String(localized: "sidebar.claudeUsage.tooltip.fiveHour", defaultValue: "5-hour limit: %d%% used"),
                usedReset: String(
                    localized: "sidebar.claudeUsage.tooltip.fiveHourReset",
                    defaultValue: "5-hour limit: %1$d%% used, resets %2$@"
                )
            ))
        }
        if let window = usage.sevenDay {
            lines.append(line(
                window,
                used: String(localized: "sidebar.claudeUsage.tooltip.weekly", defaultValue: "Weekly limit: %d%% used"),
                usedReset: String(
                    localized: "sidebar.claudeUsage.tooltip.weeklyReset",
                    defaultValue: "Weekly limit: %1$d%% used, resets %2$@"
                )
            ))
        }
        let text = lines.joined(separator: "\n")
        toolTip = text
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }
}
