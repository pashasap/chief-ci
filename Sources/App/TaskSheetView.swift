import SwiftUI
import Core

/// Renders the Core `TaskSheetScreen` description and nothing else.
struct TaskSheetView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var source: OpenedCapture?
    @State private var model: TaskSheetModel
    @State private var now = Date()
    @State private var picking = false
    @State private var pickedDay = Date()

    init(handle: String, environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: TaskSheetModel(
            handle: handle, inbox: environment.inbox, decisions: environment.decisions,
            corrections: environment.corrections))
    }

    private var screen: TaskSheetScreen { TaskSheetScreen(model: model) }

    var body: some View {
        let _ = now  // reading it makes the view redraw when the Dropped bar expires
        let screen = screen
        NavigationStack {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(screen)
                    status(screen)
                    decisions(screen)
                    moveIt(screen)
                    corrections(screen)
                    if let confirmation = screen.removeConfirmation {
                        Text(confirmation.message).wrapping()
                        button(confirmation.confirm, screen)
                        button(confirmation.cancel, screen)
                    }
                }
                .padding(16)
            }
            if let bar = screen.bar { barView(bar, screen) }
        }
        .background(Theme.background)
        .task(id: screen.bar?.message) { await expireBar() }
        .sheet(isPresented: $picking) { datePicker(screen) }
        .sheet(item: $source) { CaptureSheet(model: $0.model, environment: environment, close: { source = nil }) }
        .navigationTitle(screen.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(screen.doneLabel) { dismiss() }.touchTarget() } }
        .onChange(of: model.isClosed) { _, closed in if closed { dismiss() } }
        }
    }

    private func header(_ screen: TaskSheetScreen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(screen.text).foregroundStyle(Theme.text).lineLimit(screen.lineLimit).wrapping()
            if let note = screen.note { Text(note).font(.callout).foregroundStyle(Theme.secondaryText).wrapping() }
            if screen.handleIsSmall { Text(screen.handle).font(.caption2).foregroundStyle(Theme.secondaryText) }
            if let capture = screen.sourceCapture {
                Text(capture.text).font(.callout).foregroundStyle(Theme.secondaryText).lineLimit(3).wrapping()
                Button(screen.sourceLabel) { if let model = environment.capture(id: capture.id) { source = OpenedCapture(model: model) } }.touchTarget()
            }
        }
    }

    @ViewBuilder private func status(_ screen: TaskSheetScreen) -> some View {
        if let notice = screen.notice { Text(notice).foregroundStyle(Theme.amber).wrapping() }
        if let message = screen.message { Text(message).foregroundStyle(Theme.amber).wrapping() }
        if let caption = screen.stateCaption { Text(caption).font(.caption).foregroundStyle(Theme.amber) }
        KitLineBar { TaskSheetScreen(model: model).kitLine }
    }

    private func decisions(_ screen: TaskSheetScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(screen.elements.enumerated()), id: \.offset) { _, element in
                switch element {
                case .control(let control): button(control, screen)
                case .gap: Spacer().frame(height: 12)
                case .textField: EmptyView()
                }
            }
            if let confirmation = screen.confirmation {
                Text(confirmation.message).foregroundStyle(Theme.text).wrapping()
                HStack {
                    button(confirmation.confirm, screen)
                    button(confirmation.cancel, screen)
                }
            }
        }
    }

    private func moveIt(_ screen: TaskSheetScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(screen.moveLabel).font(.headline).foregroundStyle(Theme.text)
            ForEach(Array(screen.moveChoices.enumerated()), id: \.offset) { _, control in
                if case .move(_, .pickDate) = control.action {
                    ControlButton(control: control) { picking = true }
                } else {
                    button(control, screen)
                }
            }
        }
    }

    private func corrections(_ screen: TaskSheetScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(screen.corrections.enumerated()), id: \.offset) { index, control in
                if index == screen.corrections.count - 1, let field = screen.textField {
                    TextField(field.placeholder, text: draft, axis: .vertical).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(field.placeholder)
                }
                button(control, screen)
            }
        }
    }

    private func button(_ control: InboxControl, _ screen: TaskSheetScreen) -> some View {
        ControlButton(control: control) { Task { await screen.perform(control) } }
    }

    private var draft: Binding<String> {
        Binding(
            get: { model.drafts.texts[model.handle] ?? "" },
            set: { model.drafts.texts[model.handle] = $0 })
    }

    private func datePicker(_ screen: TaskSheetScreen) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    DatePicker(screen.dateTitle, selection: $pickedDay, in: screen.minimumDate..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Button(screen.moveHereLabel) {
                        picking = false
                        let day = pickedDay
                        Task { await screen.pick(date: screen.dateText(day)) }
                    }.touchTarget()
                }.padding(16)
            }
            .navigationTitle(screen.dateTitle)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(screen.cancelLabel) { picking = false }.touchTarget() } }
            .onAppear { pickedDay = max(pickedDay, screen.minimumDate) }
        }
    }

    private static func dayText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func barView(_ bar: TodayBar, _ screen: TaskSheetScreen) -> some View {
        HStack {
            Text(bar.message).wrapping()
            Spacer()
            button(bar.undo, screen)
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
