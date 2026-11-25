import SwiftUI
import Core

struct HomeHeaderActions {
    var onOpenSettings: () -> Void = {}
    var onOpenSearch: () -> Void = {}
    var onOpenInbox: () -> Void = {}
    var onOpenToday: () -> Void = {}
    var onClearFocus: () -> Void = {}
    var onTapWeather: () -> Void = {}
}

/// Top bar, weather + greeting, borderless live date hero, and collapsible active-focus banner.
struct HomeHeroHeaderView: View {
    let screen: HomeScreen
    let actions: HomeHeaderActions
    var weather: WeatherLocationModel = .shared

    var body: some View {
        VStack(spacing: 12) {
            topBar
            heroRow
            dragHandle
            if let focus = screen.activeFocus {
                activeFocusBanner(focus)
            }
        }
    }

    private var topBar: some View {
        HStack {
            KitRookMarkView(action: actions.onOpenSettings)
            Spacer()
            HStack(spacing: 10) {
                searchButton
                inboxBellButton
            }
        }
    }

    private var searchButton: some View {
        Button(action: actions.onOpenSearch) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                .liquidGlassCircle(tint: Theme.accent)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search tasks")
    }

    private var inboxBellButton: some View {
        Button(action: actions.onOpenInbox) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                    .liquidGlassCircle(tint: Theme.glowBlue)
                if screen.needsAttentionCount > 0 {
                    Text("\(screen.needsAttentionCount)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(Theme.primaryWhite)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.glowBlue, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
        .accessibilityLabel("Inbox, \(screen.needsAttentionCount) items awaiting action")
    }

    private var heroRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                greetingBlock
                Spacer(minLength: 8)
                borderlessDateButton(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 10) {
                greetingBlock
                borderlessDateButton(alignment: .leading)
            }
        }
        .padding(.top, 4)
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            weatherPill
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.greetingPrefix)
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.heroStart, Theme.heroMid, Theme.heroEnd],
                        startPoint: .leading, endPoint: .trailing))
                    .minimumScaleFactor(0.75)
                Text(screen.greetingName)
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(Theme.primaryWhite)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var weatherPill: some View {
        Button(action: actions.onTapWeather) {
            HStack(spacing: 6) {
                Image(systemName: weather.badgeSymbolName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.glowAmber, Theme.heroStart)
                    .font(.subheadline)
                Text(weather.badgeTemperatureText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.primaryWhite.opacity(0.08), in: Capsule())
            .frame(minHeight: Theme.minimumTapTarget, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weather.badgeAccessibilityLabel)
    }

    private func borderlessDateButton(alignment: HorizontalAlignment) -> some View {
        Button(action: actions.onOpenToday) {
            VStack(alignment: alignment, spacing: 0) {
                Text(screen.weekday)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.text.opacity(0.8))
                Text(screen.dayNumber)
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.heroStart, Theme.heroMid],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .monospacedDigit()
                Text(screen.monthName)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.text)
            }
            .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(screen.weekday) \(screen.dayNumber) \(screen.monthName), Open Today")
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Theme.primaryWhite.opacity(0.22))
            .frame(width: 36, height: 4)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    private func activeFocusBanner(_ focus: FocusFilter) -> some View {
        HStack(spacing: 10) {
            Image(systemName: focus.iconName)
                .foregroundStyle(Theme.color(focus.tokenColor))
            Text("Active Focus: \(focus.label)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .wrapping()
            Spacer()
            Button("Clear", action: actions.onClearFocus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.minimumTapTarget)
                .background(Theme.primaryWhite.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .liquidGlassTile(glow: .teal)
    }
}
