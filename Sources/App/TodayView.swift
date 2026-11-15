import SwiftUI
import Core

/// Renders the Core `TodayScreen` description and nothing else.
struct TodayView: View {
    let model: TodayModel
    let inbox: InboxModel
    let environment: AppEnvironment
    @State private var sheetHandle: String?
    private var selected: Int { model.selectedSegment }
    @State private var now = Date()

    private var screen: TodayScreen { TodayScreen(model: model) }

    var body: some View {
        let _ = now  // reading it makes the view redraw when the Done bar expires
        let screen = screen
        let segments = screen.segments
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        notes(screen)
                        Picker(screen.segmentLabel, selection: Binding(get: { selected }, set: { model.selectedSegment = $0 })) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                                Text("\(segment.title) \(segment.count)").tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                        if segments.indices.contains(selected) { segmentView(segments[selected], screen) }
                    }
                    .padding(16)
                }

            }
            .background(Theme.background)
            .navigationTitle(screen.header)
            .refreshable { await inbox.pullToRefresh() }
        }
        .sheet(isPresented: sheetOpen) {
            if let handle = sheetHandle { TaskSheetView(handle: handle, environment: environment) }
        }
        .task(id: screen.bar?.undo.action) { await expireBar() }
    }

    private var sheetOpen: Binding<Bool> {
        Binding(get: { sheetHandle != nil }, set: { if !$0 { sheetHandle = nil } })
    }

    @ViewBuilder private func notes(_ screen: TodayScreen) -> some View {
        if !screen.updatedText.isEmpty { Text(screen.updatedText).foregroundStyle(Theme.secondaryText).wrapping() }
        if let text = screen.notice { Text(text).foregroundStyle(Theme.amber).wrapping() }
        if let text = screen.message { Text(text).foregroundStyle(Theme.amber).wrapping() }
        KitLineBar { TodayScreen(model: model).kitLine }
    }

    @ViewBuilder private func segmentView(_ segment: TodaySegment, _ screen: TodayScreen) -> some View {
        if let intro = segment.intro { Text(intro).foregroundStyle(Theme.secondaryText).wrapping() }
        if let empty = segment.emptyText { Text(empty).foregroundStyle(Theme.secondaryText).wrapping() }
        ForEach(segment.tasks, id: \.handle) { taskRow($0, screen) }
        ForEach(segment.waiting, id: \.handle) { waitingCard($0, screen) }
        ForEach(segment.ideas, id: \.handle) { idea in
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.text).wrapping()
                if let note = idea.note { Text(note).font(.footnote).foregroundStyle(Theme.secondaryText).wrapping() }
                Text(idea.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            .card()
        }
    }

    private func taskRow(_ row: TodayTaskRow, _ screen: TodayScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { sheetHandle = row.handle } label: {
                Text(row.text).lineLimit(row.textLineLimit).strikethrough(row.isStruck)
                    .foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.text)
            Text(row.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
            HStack {
                Text(row.pill).font(.caption).foregroundStyle(Theme.secondaryText)
                if let mark = row.overdueMark { Text(mark).font(.caption.bold()).foregroundStyle(Theme.destructive) }
            }
            if let note = row.note, let limit = row.noteLineLimit {
                Text(note).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(limit)
            }
            controls(row.controls, screen)
        }
        .card()
    }

    private func waitingCard(_ card: TodayWaitingCard, _ screen: TodayScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.handle).font(.caption2).foregroundStyle(Theme.secondaryText)
            Text(card.text).wrapping()
            controls(card.controls, screen)
        }
        .card()
    }

    private func controls(_ controls: [InboxControl], _ screen: TodayScreen) -> some View {
        HStack {
            ForEach(Array(controls.enumerated()), id: \.offset) { _, control in
                ControlButton(control: control) { Task { await screen.perform(control) } }
            }
        }
    }

    private func barView(_ bar: TodayBar, _ screen: TodayScreen) -> some View {
        HStack {
            Text(bar.message)
            Spacer()
            ControlButton(control: bar.undo) { Task { await screen.perform(bar.undo) } }
        }
        .padding(.horizontal, 16)
        .background(Theme.card)
    }

    /// The bar disappears 5 seconds after it appears; the model decides, this only asks for a redraw.
    private func expireBar() async {
        guard screen.bar != nil else { return }
        try? await Task.sleep(for: .seconds(DecisionModel.undoWindow + 0.1))
        now = Date()
    }
}

private extension View {
    func card() -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
