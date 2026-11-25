import SwiftUI
import Core

/// Keeps a row at its intrinsic width; if it cannot fit, its controls remain reachable by scrolling.
struct FittingHorizontalRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content.fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal) { content }
        }
    }
}

struct BottomBarView: View {
    let screen: BottomBarScreen
    let selected: AppTab
    let select: (BottomBarKind) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(screen.rows.enumerated()), id: \.offset) { _, items in
                dockRow(items)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.ambientSecondary.opacity(0.68))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.primaryWhite.opacity(0.14)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func dockRow(_ items: [BottomBarItem]) -> some View {
        if screen.usesEqualWidthColumns {
            HStack(alignment: .center, spacing: 0) {
                ForEach(items, id: \.kind) { item in
                    slotView(item).frame(maxWidth: .infinity)
                }
            }
        } else {
            FittingHorizontalRow {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(items, id: \.kind) { item in
                        slotView(item).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slotView(_ item: BottomBarItem) -> some View {
        if item.raised {
            Color.clear
                .frame(minWidth: item.minimumWidth, minHeight: item.minimumHeight)
                .frame(height: item.size)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            tabButton(item)
        }
    }

    private func tabButton(_ item: BottomBarItem) -> some View {
        Button { select(item.kind) } label: {
            tabLabel(item)
                .frame(minWidth: item.minimumWidth, minHeight: item.minimumHeight,
                    alignment: item.iconTopAligned ? .top : .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected(item.kind) ? .isSelected : [])
    }

    private func tabLabel(_ item: BottomBarItem) -> some View {
        let style = presentation(item.kind)
        return VStack(spacing: item.badgeGap) {
            iconRow(item)
            Text(item.label)
                .font(.caption2)
                .lineLimit(item.labelLineLimit)
                .minimumScaleFactor(item.labelMinimumScaleFactor)
                .fixedSize(horizontal: screen.wrapsWholeWords, vertical: true)
        }
        .fontWeight(style?.weight == .semibold ? .semibold : .regular)
        .foregroundStyle(style.map { Theme.color($0.label) } ?? Theme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if let fill = style?.fill, style?.shape == .capsule {
                Capsule().fill(Theme.color(fill).opacity(0.85))
            }
        }
    }

    private func presentation(_ kind: BottomBarKind) -> TabPresentation? {
        screen.tabPresentations(selected: selected).first { $0.kind == kind }
    }

    private func iconRow(_ item: BottomBarItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: item.symbol)
                .font(.body.weight(.medium))
                .frame(width: item.iconFrame.width, height: item.iconFrame.height)
            if item.reservesBadgeSpace || item.badge != nil {
                Text(item.badge ?? " ")
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.badge == nil ? .clear : Theme.recordButton, in: Capsule())
                    .foregroundStyle(item.badge == nil ? .clear : Theme.recordText)
                    .opacity(item.badge == nil ? 0 : 1)
                    .frame(minHeight: item.badgeFrame.height)
                    .offset(x: item.badgeFrame.minX - item.iconFrame.maxX + item.badgeFrame.width / 2,
                            y: item.badgeFrame.minY - item.iconFrame.minY)
                    .accessibilityHidden(item.badge == nil)
            }
        }
    }

    private func isSelected(_ kind: BottomBarKind) -> Bool {
        switch kind {
        case .home: return selected == .home
        case .inbox: return selected == .inbox
        case .tasks: return selected == .today
        case .settings: return selected == .settings
        case .record, .write: return false
        }
    }
}

extension View {
    /// Every control is at least 44 by 44 points.
    func touchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    /// Text wraps instead of clipping.
    func wrapping() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder func auditRoot(_ identifier: String?) -> some View {
        if let identifier { accessibilityElement(children: .contain).accessibilityIdentifier(identifier) }
        else { self }
    }
}
