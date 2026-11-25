import Foundation

extension InboxScreen {
    /// Runs the decision a control stands for. Opening the change field and Undo send nothing:
    /// the contract has no inverse command, so Undo only appears while the model reports it.
    public func perform(_ action: InboxAction, drafts: InboxDrafts) async {
        let snapshot = inbox.snapshot
        switch action {
        case .approve(let handle):
            if let proposal = proposal(handle, in: snapshot) { await decisions.approve(proposal) }
        case .reject(let handle):
            if let proposal = proposal(handle, in: snapshot) { await decisions.reject(proposal) }
        case .dropProposal(let handle):
            if let proposal = proposal(handle, in: snapshot) { await decisions.drop(proposal) }
        case .sendChange(let handle):
            if let proposal = proposal(handle, in: snapshot) {
                await decisions.change(proposal, text: drafts.texts[handle] ?? "")
            }
        case .option(let handle, let index):
            if let question = question(handle, in: snapshot) { await decisions.answer(question, optionIndex: index) }
        case .sendAnswer(let handle):
            if let question = question(handle, in: snapshot) {
                await decisions.answer(question, text: drafts.texts[handle] ?? "")
            }
        case .pair: inbox.coordinator?.selectedTab = .settings
        case .retryUpload: await inbox.loop?.retryNow()
        case .retry:
            await decisions.retry()
        case .undo: await decisions.undoLastAction()
        case .openChange, .confirmRemove, .cancelRemove, .justAnIdea, .itsATask, .notThis, .sendCorrection,
            .markDone, .reopen, .closeWaiting, .dropTask, .confirmDrop, .cancelDrop, .move, .taskMore,
            .closeTaskMore, .augmentIdea, .researchIdea, .deleteIdea, .confirmDeleteIdea, .cancelDeleteIdea:
            break
        }
    }

    private func proposal(_ handle: String, in snapshot: Snapshot?) -> Proposal? {
        snapshot?.proposals.first { $0.handle == handle }
    }

    private func question(_ handle: String, in snapshot: Snapshot?) -> Question? {
        snapshot?.questions.first { $0.handle == handle }
    }
}
