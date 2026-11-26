import SwiftUI
import UIKit
import Core

struct TileViewCallbacks {
    var onAction: (TileActionKind) -> Void
    var onEdit: (UniversalTaskTile) -> Void
    var onRate: (FramingSignal, UniversalTaskTile) -> Void
    var onMove: ((TileMoveTarget) -> Void)? = nil
    var onTapTitle: (() -> Void)? = nil
    var onToggleExpansion: (() -> Void)? = nil
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
    @State private var showingMoveDialog = false
    @State private var showingMoreDialog = false

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
            if !tile.moveOptions.isEmpty { moveMenu }
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

    /// The one Move control: its items are the tile's move option labels.
    private var moveMenu: some View {
        Button { showingMoveDialog = true } label: {
            Image(systemName: SuggestionIcon.more.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UniversalTaskTile.moveMenuAccessibleName)
        .disabled(!tile.isEnabled || tile.isPending)
        .accessibilityHint(tile.moveDisabledReason ?? "")
        .confirmationDialog(UniversalTaskTile.moveMenuAccessibleName, isPresented: $showingMoveDialog,
                            titleVisibility: .hidden) {
            ForEach(Array(tile.moveOptions.enumerated()), id: \.offset) { _, option in
                Button(option.label) { callbacks.onMove?(option.target) }
                    .accessibilityLabel(option.accessibilityLabel)
            }
        }
    }

    private var moreMenu: some View {
        Button { showingMoreDialog = true } label: {
            Image(systemName: SuggestionIcon.more.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UniversalTaskTile.moreMenuAccessibleName)
        .confirmationDialog(UniversalTaskTile.moreMenuAccessibleName, isPresented: $showingMoreDialog,
                            titleVisibility: .hidden) {
            contextMenuItems
        }
    }

    @ViewBuilder private var bodyBlock: some View {
        titleButton
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

    /// The text block itself: tap shows all of the tile's text, a second tap clamps it again.
    private var titleButton: some View {
        Button {
            callbacks.onToggleExpansion?()
        } label: {
            titleContent()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.fullText)
        .accessibilityValue(tile.isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(tile.isExpanded ? "Tap to collapse to three lines" : "Tap to show all text")
    }

    @ViewBuilder private var actionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                actionPair(.approve, .reject)
                actionPair(.delete, .deferItem)
            }
        } else if !tile.visibleActions.isEmpty {
            HStack(spacing: 6) {
                ForEach(tile.visibleActions, id: \.self) { kind in
                    actionButton(kind)
                }
            }
        }
    }

    /// Two actions on one line at Accessibility XL; an action the tile hides drops out of the pair.
    @ViewBuilder private func actionPair(_ first: TileActionKind, _ second: TileActionKind) -> some View {
        if tile.visibleActions.contains(first) || tile.visibleActions.contains(second) {
            HStack(spacing: 8) {
                if tile.visibleActions.contains(first) { actionButton(first) }
                if tile.visibleActions.contains(second) { actionButton(second) }
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
        if tile.visibleActions.contains(.approve) {
            Button("Approve") { callbacks.onAction(.approve) }
        }
        if tile.visibleActions.contains(.reject) {
            Button("Reject") { callbacks.onAction(.reject) }
        }
        if tile.visibleActions.contains(.delete) {
            Button("Delete") { confirmingDelete = true }
        }
        if tile.visibleActions.contains(.deferItem) {
            Button("Defer") { callbacks.onAction(.deferItem) }
        }
        Button("Change") { callbacks.onEdit(tile) }
        Button("Good Framing") { callbacks.onRate(.up, tile) }
        Button("Bad Framing") { callbacks.onRate(.down, tile) }
        if let tapTitle = callbacks.onTapTitle {
            Button("Task details") { tapTitle() }
        }
    }

    @ViewBuilder private var swipeUnderlay: some View {
        if dragOffset > 8, tile.visibleActions.contains(.approve) {
            HStack {
                Label("Approve", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.emeraldApprove)
                    .padding(.leading, 18)
                Spacer()
            }
        } else if dragOffset < -8, tile.visibleActions.contains(.reject) {
            HStack {
                Spacer()
                Label("Reject", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.roseReject)
                    .padding(.trailing, 18)
            }
        }
    }

    /// A tile that hides its promotion actions, like a Later candidate, cannot be swiped either.
    private var allowsSwipe: Bool { tile.isEnabled && !tile.visibleActions.isEmpty }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard allowsSwipe, abs(value.translation.width) > abs(value.translation.height) * 1.25 else {
                    dragOffset = 0
                    return
                }
                dragOffset = max(-120, min(120, value.translation.width))
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if allowsSwipe && abs(horizontal) > abs(vertical) {
                    if horizontal > 72, tile.visibleActions.contains(.approve) {
                        triggerSwipe(.approve, style: .medium, text: "Approved \(tile.title)")
                    } else if horizontal < -72, tile.visibleActions.contains(.reject) {
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
            .lineLimit(tile.resolvedTextLineLimit)
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
