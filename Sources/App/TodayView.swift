import SwiftUI
import UIKit
import Core

/// Renders the Core `TodayScreen` description and nothing else.
struct TodayView: View {
    let model: TodayModel
    let inbox: InboxModel
    let environment: AppEnvironment
    var layoutSize: CGSize = CGSize(width: 390, height: 844)
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var sheetHandle: String?
    private var selected: Int { model.selectedSegment }
    @State private var now = Date()

    private var screen: TodayScreen {
        TodayScreen(model: model).presented(in: RecordingPanelLayout(
            width: layoutSize.width, height: layoutSize.height, largestText: textSize.isAccessibilitySize))
    }

    var body: some View {
        let _ = now  // reading it makes the view redraw when the Done bar expires
        let screen = screen
        let segments = screen.segments
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if textSize.isAccessibilitySize {
                            Text(screen.header)
                                .font(.largeTitle.bold())
                                .foregroundStyle(Theme.text)
                                .lineLimit(screen.headerLineLimit)
                                .wrapping()
                                .accessibilityAddTraits(.isHeader)
                        }
                        notes(screen)
                        segmentSelector(segments, screen)
                        if segments.indices.contains(selected) { segmentView(segments[selected], screen) }
                    }
                    .padding(16)
                }
            }
            .background(Theme.background)
            .navigationTitle(textSize.isAccessibilitySize ? "" : screen.header)
            .navigationBarTitleDisplayMode(textSize.isAccessibilitySize ? .inline : .automatic)
            .refreshable { await inbox.pullToRefresh() }
        }
        .sheet(isPresented: sheetOpen) {
            if let handle = sheetHandle { TaskSheetView(handle: handle, environment: environment) }
        }
        .sheet(isPresented: moreOpen) { metadataSheet(screen) }
        .task(id: screen.bar?.undo.action) { await expireBar() }
    }

    @ViewBuilder private func metadataSheet(_ screen: TodayScreen) -> some View {
        if let metadata: TaskMetadataScreen = screen.more {
            TaskMetadataView(screen: metadata) { Task { await screen.perform(metadata.done) } }
        }
    }

    private func draftBinding(_ handle: String) -> Binding<String> {
        Binding(
            get: { inbox.drafts.texts[handle] ?? "" },
            set: { inbox.drafts.texts[handle] = $0 })
    }

    private var moreOpen: Binding<Bool> {
        Binding(get: { screen.more != nil }, set: { if !$0 { model.moreHandle = nil } })
    }

    private var sheetOpen: Binding<Bool> {
        Binding(get: { sheetHandle != nil }, set: { if !$0 { sheetHandle = nil } })
    }

    @ViewBuilder private func segmentSelector(_ segments: [TodaySegment], _ screen: TodayScreen) -> some View {
        if screen.scalableText && screen.scrollsSegmentSelector {
            ScrollView(.horizontal) {
                AccessibleTodaySegments(segments: segments, label: screen.segmentLabel, select: screen.selectSegment)
            }
        } else {
            Picker(screen.segmentLabel, selection: Binding(get: { selected }, set: { screen.selectSegment($0) })) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Text(segment.label).lineLimit(segment.lineLimit).tag(index)
                }
            }
            .pickerStyle(.segmented)
        }
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
            TodayIdeaCard(idea: idea, draft: draftBinding(idea.handle)) { control in
                Task { await screen.perform(control) }
            }
        }
    }

    private func taskRow(_ row: TodayTaskRow, _ screen: TodayScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { sheetHandle = row.handle } label: {
                Text(row.text).lineLimit(row.textLineLimit).strikethrough(row.isStruck)
                    .foregroundStyle(Theme.text).wrapping()
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.text)
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

/// A native segmented control keeps the accessibility hierarchy while its titles grow with Dynamic Type.
private struct AccessibleTodaySegments: UIViewRepresentable {
    let segments: [TodaySegment]
    let label: String
    let select: (Int) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var pointSize: CGFloat = 15

    private var font: UIFont { .systemFont(ofSize: pointSize, weight: .medium) }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: segments.map(\.accessibilityLabel))
        control.accessibilityLabel = label
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.select = select
        control.setTitleTextAttributes([.font: font], for: .normal)
        control.setTitleTextAttributes([.font: font], for: .selected)
        for (index, segment) in segments.enumerated() {
            if control.titleForSegment(at: index) != segment.accessibilityLabel {
                control.setTitle(segment.accessibilityLabel, forSegmentAt: index)
            }
            control.setWidth(width(for: segment), forSegmentAt: index)
        }
        control.selectedSegmentIndex = segments.firstIndex(where: \.isSelected) ?? UISegmentedControl.noSegment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        let width = segments.reduce(CGFloat.zero) { $0 + self.width(for: $1) }
        let minimumHeight = segments.map(\.minimumHeight).max() ?? 44
        return CGSize(width: width, height: max(minimumHeight, ceil(font.lineHeight) + 20))
    }

    private func width(for segment: TodaySegment) -> CGFloat {
        let labelWidth = (segment.accessibilityLabel as NSString).size(withAttributes: [.font: font]).width
        return max(segment.minimumWidth, ceil(labelWidth) + 28)
    }

    @MainActor final class Coordinator: NSObject {
        var select: (Int) -> Void = { _ in }

        @objc func changed(_ control: UISegmentedControl) { select(control.selectedSegmentIndex) }
    }
}

private extension View {
    func card() -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
