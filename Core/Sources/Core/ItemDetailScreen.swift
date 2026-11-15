import Foundation

/// The models an item detail reads from and sends through.
@MainActor
public struct ItemDetailSources {
    public let inbox: InboxModel
    public let decisions: DecisionModel
    public let corrections: CorrectionModel

    public init(inbox: InboxModel, decisions: DecisionModel, corrections: CorrectionModel) {
        self.inbox = inbox
        self.decisions = decisions
        self.corrections = corrections
    }
}

/// Everything the item detail shows, as plain values read from the models. The view renders this and nothing else.
/// Its initialiser is the compiler's memberwise one: `ItemDetailScreen(handle:inbox:decisions:corrections:drafts:)`.
@MainActor
public struct ItemDetailScreen {
    public let handle: String
    let inbox: InboxModel
    let decisions: DecisionModel
    let corrections: CorrectionModel
    var drafts: InboxDrafts = InboxDrafts()

    /// The screen for `handle`, as the app builds it.
    public static func make(handle: String, sources: ItemDetailSources, drafts: InboxDrafts) -> ItemDetailScreen {
        ItemDetailScreen(
            handle: handle, inbox: sources.inbox, decisions: sources.decisions,
            corrections: sources.corrections, drafts: drafts)
    }

    public var removeConfirmation: TaskSheetConfirmation? {
        guard corrections.removeConfirming.contains(handle) else { return nil }
        let gate = RowGate(state: nil, enabled: decisions.canDecide, reason: decisions.cannotDecideReason)
        let builder = InboxRowBuilder(decisions: decisions, drafts: drafts)
        return TaskSheetConfirmation(message: "Remove this item?", confirm: builder.make("Remove", .confirmRemove(handle), role: .destructive, gate: gate),
            cancel: builder.make("Keep it", .cancelRemove(handle), gate: RowGate(state: nil, enabled: true, reason: nil)))
    }
    public var shouldClose: Bool { decisions.shouldCloseSheet(handle: handle) }
    public var sourceCapture: Capture? { inbox.sourceCapture(for: handle) }
    public var sourceLabel: String { "Source capture" }
    public var title: String { "Item" }
    public var handleIsSmall: Bool { true }

    /// Nil: the full text is never clamped.
    public var lineLimit: Int? { nil }

    private var row: InboxScreenRow? {
        InboxRowBuilder(decisions: decisions, drafts: drafts).itemRow(handle: handle, snapshot: inbox.snapshot)
    }

    public var text: String { row?.text ?? "" }
    public var kicker: String? { row?.kicker }
    public var because: String? { row?.because }
    public var state: DecisionState? { row?.state }
    public var elements: [InboxElement] { row?.elements ?? [] }
    public var controls: [InboxControl] { row?.controls ?? [] }
    public var textField: InboxTextField? { row?.textField }

    /// "Sending" or "Did not go through" for this item's last command.
    public var stateCaption: String? { row?.stateCaption }

    /// Kit's line after a confirmed command.
    public var kitLine: String? { decisions.kitLine }

    /// The offline reason, while corrections and decisions are blocked.
    public var notice: String? { decisions.cannotDecideReason }

    /// Runs what `control` stands for. A disabled control sends nothing.
    public func perform(_ control: InboxControl, drafts: InboxDrafts) async {
        guard control.isEnabled else { return }
        switch control.action {
        case .justAnIdea(let handle): await corrections.justAnIdea(handle: handle)
        case .itsATask(let handle): await corrections.itsATask(handle: handle)
        case .notThis(let handle): corrections.removeConfirming.insert(handle)
        case .cancelRemove(let handle): corrections.removeConfirming.remove(handle)
        case .confirmRemove(let handle):
            guard corrections.removeConfirming.remove(handle) != nil else { return }
            await corrections.notThis(handle: handle)
        case .sendCorrection(let handle):
            await corrections.correct(handle: handle, text: drafts.texts[handle] ?? "")
        default:
            await InboxScreen(inbox: inbox, decisions: decisions, drafts: drafts).perform(control.action, drafts: drafts)
        }
    }
}
