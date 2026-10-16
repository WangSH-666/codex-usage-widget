import SwiftUI
import AppKit
import UsageCore

struct WidgetView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: Preferences
    let showMenu: (NSEvent) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        Group {
            if preferences.layout == "tokens" {
                HStack(alignment: .center, spacing: 12) {
                    total.frame(width: 96, alignment: .leading)
                    Rectangle().fill(.primary.opacity(0.08)).frame(width: 0.5, height: 88)
                    quotaPair(compact: true)
                }
            } else {
                quotaPair(compact: false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(width: preferences.cardSize.width, height: preferences.cardSize.height)
        .background {
            ZStack {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? 0.46 : 0.56))
                        .glassEffect(.regular, in: shape)
                }
                shape.strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.55), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.19 : 0.1), radius: 7, x: 0, y: 2)
            // Fade the complete glass surface, never the content or native drag layer.
            .opacity(reduceTransparency ? 1 : preferences.opacity)
        }
        .overlay { WindowDragSurface(showMenu: showMenu).accessibilityHidden(true) }
        .padding(8)
        .preferredColorScheme(preferences.colorScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.stats?.dailyTokens)
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("24小时 Token").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(store.stats?.millions ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
                Text("M").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if store.scanError != nil {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange)
                        .accessibilityLabel("本机用量读取失败，右键查看状态")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.stats.map { "过去24小时，\($0.dailyTokens) tokens" } ?? "正在读取过去24小时用量")
    }

    private func quotaPair(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: compact ? 12 : 28) {
            quota(title: "5小时", window: store.quota?.primary, minutes: 300, color: Color(nsColor: preferences.primaryRingColor), compact: compact)
            quota(title: "1周", window: store.quota?.secondary, minutes: 10080, color: Color(nsColor: preferences.secondaryRingColor), compact: compact)
        }
    }

    private func compactResetLabel(_ label: String, compact: Bool) -> String {
        guard compact, let space = label.firstIndex(of: " "), label[..<space].contains("日") else { return label }
        return label.replacingCharacters(in: space...space, with: "\n")
    }

    private func quota(title: String, window: QuotaWindow?, minutes: Int, color: Color, compact: Bool) -> some View {
        let remaining = store.quotaIsStale ? nil : window?.remaining(expectedMinutes: minutes, now: store.now)
        let tint = remaining.map { $0 <= 20 ? Color.orange : color } ?? color
        let matchingWindow = window?.windowDurationMins == minutes
        let reset = remaining != nil && matchingWindow ? window!.resetLabel(now: store.now) :
            (store.syncing ? "正在同步" : matchingWindow && window?.resetsAt != nil ? "等待更新" : "暂无数据 · 右键查看")
        // Include the stroke in layout bounds so visual top/bottom insets match.
        let ringSize: CGFloat = compact ? 74 : 104
        let stroke: CGFloat = compact ? 8 : 12
        return VStack(spacing: 0) {
            ZStack {
                Circle().strokeBorder(color.opacity(0.14), lineWidth: stroke)
                if let remaining {
                    Circle().inset(by: stroke / 2).trim(from: 0, to: remaining / 100)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: compact ? 21 : 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: ringSize - 2 * stroke - 4, height: ringSize, alignment: .center)
            }
            .frame(width: ringSize, height: ringSize)
            .padding(.bottom, compact ? 5 : 6)
            Text(title).font(.system(size: compact ? 11 : 13, weight: .semibold))
                .padding(.bottom, 3)
            Text(compactResetLabel(reset, compact: compact))
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(.primary.opacity(scheme == .dark ? 0.7 : 0.65))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : 1)
                .minimumScaleFactor(0.85)
                .frame(height: compact ? 26 : 14, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(remaining.map { String(format: "剩余%.0f%%", $0) } ?? "暂无数据")，\(reset)")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: remaining)
    }
}
