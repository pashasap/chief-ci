import SwiftUI
import UIKit
import Core

struct TileViewCallbacks {
    var onAction: (TileActionKind) -> Void
    var onEdit: (UniversalTaskTile) -> Void
    var onRate: (FramingSignal, UniversalTaskTile) -> Void
    var onTapTitle: (() -> Void)? = nil
}

struct TileEditTarget: Identifiable, Equatable {
    let id: String
    let sourceKind: TileSourceKind
    let title: String
}

/// Unified Obsidian Liquid Glass tile across Inbox, Tasks, and Search.
struct UniversalTaskTileView<TitleContent: View>: View {
    let tile: UniversalTaskTile
    let callbacks: TileViewCallbacks
    @ViewBuilder let titleContent: () -> TitleContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            swipeUnderlay
            cardSurface
                .offset(x: dragOffset)
                .gesture(swipeGesture)
                .contextMenu { contextMenuItems }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions { accessibilityActions }
        .alert("Delete item?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { callbacks.onAction(.delete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(tile.title)
        }
    }

    private var cardSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            bodyBlock
            actionRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: glowTone(for: tile.bucket))
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            pillBadge
            Spacer(minLength: 4)
            metaView
            moreMenu
        }
    }

    private var pillBadge: some View {
        let color = Theme.color(tile.badgeColor)
        return Text(badgeText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.75))
            .wrapping()
    }

    private var badgeText: String {
        var parts = [tile.tagLabel]
        if let focus = tile.focusLabel, !focus.isEmpty { parts.append(focus) }
        if let signal = tile.framingSignal { parts.append(signal.badgeText) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var metaView: some View {
        if let overdue = tile.overdueMark {
            Text(overdue).font(.caption.weight(.semibold)).foregroundStyle(Theme.destructive)
        } else if !tile.metaLine.isEmpty {
            Text(tile.metaLine)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private var moreMenu: some View {
        Menu {
            contextMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions")
    }

    @ViewBuilder private var bodyBlock: some View {
        if let tapTitle = callbacks.onTapTitle {
            Button(action: tapTitle) {
                titleContent()
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tile.title)
        } else {
            titleContent()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let attachment = tile.attachmentName, !attachment.isEmpty {
            Label(attachment, systemImage: "paperclip")
                .font(.caption)
                .foregroundStyle(Theme.glowCyan)
                .wrapping()
        }
        if tile.isPending {
            Text("Sending").font(.caption).foregroundStyle(Theme.amber)
        }
    }

    @ViewBuilder private var actionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton(.approve)
                    actionButton(.reject)
                }
                HStack(spacing: 8) {
                    actionButton(.delete)
                    actionButton(.deferItem)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(TileActionKind.allCases, id: \.self) { kind in
                    actionButton(kind)
                }
            }
        }
    }

    private func actionButton(_ kind: TileActionKind) -> some View {
        let tint = actionColor(kind)
        return Button {
            handleActionTap(kind)
        } label: {
            Label(kind.label, systemImage: kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .wrapping()
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(tint.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .disabled(!tile.isEnabled)
        .accessibilityHint(tile.disabledReason ?? "")
    }

    private func handleActionTap(_ kind: TileActionKind) {
        if kind == .delete {
            confirmingDelete = true
        } else {
            callbacks.onAction(kind)
        }
    }

    @ViewBuilder private var contextMenuItems: some View {
        Button { callbacks.onEdit(tile) } label: {
            Label("Change", systemImage: "pencil")
        }
        Button { callbacks.onRate(.up, tile) } label: {
            Label("Good Framing 👍", systemImage: "hand.thumbsup")
        }
        Button { callbacks.onRate(.down, tile) } label: {
            Label("Bad Framing 👎", systemImage: "hand.thumbsdown")
        }
    }

    @ViewBuilder private var accessibilityActions: some View {
        Button("Approve") { callbacks.onAction(.approve) }
        Button("Reject") { callbacks.onAction(.reject) }
        Button("Delete") { confirmingDelete = true }
        Button("Defer") { callbacks.onAction(.deferItem) }
        Button("Change") { callbacks.onEdit(tile) }
        Button("Good Framing") { callbacks.onRate(.up, tile) }
        Button("Bad Framing") { callbacks.onRate(.down, tile) }
    }

    @ViewBuilder private var swipeUnderlay: some View {
        if dragOffset > 8 {
            HStack {
                Label("Approve", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.emeraldApprove)
                    .padding(.leading, 18)
                Spacer()
            }
        } else if dragOffset < -8 {
            HStack {
                Spacer()
                Label("Reject", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.roseReject)
                    .padding(.trailing, 18)
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard tile.isEnabled, abs(value.translation.width) > abs(value.translation.height) * 1.25 else {
                    dragOffset = 0
                    return
                }
                dragOffset = max(-120, min(120, value.translation.width))
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if tile.isEnabled && abs(horizontal) > abs(vertical) {
                    if horizontal > 72 {
                        triggerSwipe(.approve, style: .medium, text: "Approved \(tile.title)")
                    } else if horizontal < -72 {
                        triggerSwipe(.reject, style: .light, text: "Rejected \(tile.title)")
                    }
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }

    private func triggerSwipe(_ action: TileActionKind, style: UIImpactFeedbackGenerator.FeedbackStyle, text: String) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        AccessibilityNotification.Announcement(text).post()
        callbacks.onAction(action)
    }

    private func actionColor(_ kind: TileActionKind) -> Color {
        switch kind {
        case .approve: return Theme.emeraldApprove
        case .reject: return Theme.roseReject
        case .delete: return Theme.primaryWhite.opacity(0.84)
        case .deferItem: return Theme.amber
        }
    }

    private func glowTone(for bucket: TileBucket) -> GlassGlowTone {
        switch bucket {
        case .inbox, .ideas: return .blue
        case .today: return .amber
        case .later: return .purple
        case .waiting: return .cyan
        }
    }
}

struct UniversalTileDefaultTitle: View {
    let tile: UniversalTaskTile

    var body: some View {
        Text(tile.title)
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.text)
            .strikethrough(tile.isStruck)
            .lineLimit(tile.textLineLimit)
    }
}

extension UniversalTaskTileView where TitleContent == UniversalTileDefaultTitle {
    init(tile: UniversalTaskTile, callbacks: TileViewCallbacks) {
        self.tile = tile
        self.callbacks = callbacks
        self.titleContent = { UniversalTileDefaultTitle(tile: tile) }
    }
}

/// Built-in fallback Change sheet when KT-05's DynamicComposerSheet callback is not wired yet.
struct TileChangeComposerSheet: View {
    let target: TileEditTarget
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(target: TileEditTarget, onSubmit: @escaping (String) -> Void) {
        self.target = target
        self.onSubmit = onSubmit
        self._text = State(initialValue: target.title)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tell Kit what to change")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                TextField("Updated task or suggestion", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(12)
                    .liquidGlassTile(glow: .cyan)
                Button("Send") {
                    onSubmit(text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .touchTarget()
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(16)
            .background(AmbientScreenCanvas())
            .navigationTitle("Change")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
