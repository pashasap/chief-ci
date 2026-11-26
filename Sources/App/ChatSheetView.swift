import SwiftUI
import Core

/// Thin sheet over the Core chat model: it renders the Core screen values and forwards text.
@MainActor
struct ChatSheetView: View {
    private let screen = ChatSheetScreen()
    let environment: AppEnvironment
    let onClose: () -> Void

    @State private var chat: ChatSessionModel
    @FocusState private var composerFocused: Bool

    init(environment: AppEnvironment, onClose: @escaping () -> Void) {
        self.environment = environment
        self.onClose = onClose
        _chat = State(initialValue: environment.makeChatSession())
    }

    var body: some View {
        VStack(spacing: screen.metrics.sheetSpacing) {
            header
            turns
            notice
            composer
        }
        .padding(.vertical, screen.metrics.verticalPadding)
        .background(Theme.color(DesignTokens.surfaceDeep))
        .task { await openSession() }
        .onDisappear { chat.close() }
    }

    private var header: some View {
        HStack {
            Text(screen.labels.title)
                .font(.headline)
                .foregroundStyle(Theme.color(DesignTokens.text))
            Spacer()
            Button(screen.labels.close, action: closeChat)
                .accessibilityLabel(screen.labels.closeAccessibility)
        }
        .padding(.horizontal, screen.metrics.horizontalPadding)
    }

    private var turns: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: screen.metrics.turnSpacing) {
                    ForEach(Array(chat.turns.enumerated()), id: \.offset) { index, turn in
                        bubble(turn, index: index)
                    }
                }
                .padding(.horizontal, screen.metrics.horizontalPadding)
            }
            .onChange(of: chat.turns.count) { _, _ in
                if let last = chat.turns.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = chat.notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(Theme.color(DesignTokens.warning))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(notice)
        }
    }

    private func bubble(_ turn: ChatTurn, index: Int) -> some View {
        Text(turn.content)
            .font(.body)
            .foregroundStyle(Theme.color(DesignTokens.text))
            .padding(screen.metrics.bubblePadding)
            .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
            .background(Theme.color(DesignTokens.card), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .accessibilityLabel(screen.spokenText(for: turn))
            .id(index)
    }

    private var composer: some View {
        HStack(spacing: screen.metrics.composerSpacing) {
            TextField(screen.labels.fieldPrompt, text: Binding(
                get: { chat.draft },
                set: { chat.draft = $0 }))
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .accessibilityLabel(screen.labels.fieldAccessibility)
            Button(screen.sendTitle(isSending: chat.isSending)) {
                Task { await chat.send(text: chat.draft) }
            }
            .disabled(chat.isSending)
            .accessibilityLabel(screen.labels.sendAccessibility)
        }
        .frame(minHeight: Theme.minimumTapTarget)
        .padding(.horizontal, screen.metrics.horizontalPadding)
    }

    /// Opens the in-memory chat; the audit stop also asks its one fixed question first.
    private func openSession() async {
        chat.open()
        guard let audit = environment.audit, audit.stop.id == "chat-exchange" else { return }
        await chat.send(text: ChatSheetScreen.seedQuestion)
    }

    private func closeChat() {
        chat.close()
        onClose()
    }
}
