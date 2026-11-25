import Foundation

/// The Ideas segment: the shared `IdeaModel` rows, shown on Today.
@MainActor
struct TodayIdeaBuilder {
    let model: TodayModel

    func segment() -> TodaySegment {
        let ideas = model.ideas.rows.map(row)
        return TodaySegment(title: "Ideas", count: ideas.count, ideas: ideas, intro: TodayBuilder.ideasIntro)
    }

    func row(_ idea: IdeaRow) -> TodayIdeaRow {
        var row = TodayIdeaRow(handle: idea.handle, text: idea.text, note: idea.note)
        row.controls = idea.controls
        row.textField = idea.textField
        row.statusText = idea.statusText
        row.detailsText = idea.detailsText
        return row
    }
}
