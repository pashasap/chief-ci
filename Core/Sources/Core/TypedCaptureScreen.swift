import Foundation

public enum TypedCaptureAction: Equatable, Sendable { case save, cancel, recordInstead }

public struct TypedCaptureControl: Equatable, Sendable {
    public var label: String
    public var action: TypedCaptureAction
    public var isEnabled: Bool
    public var disabledReason: String?
}

public enum TypedFieldStyle: Equatable, Sendable { case plain }

public struct TypedCaptureField: Equatable, Sendable {
    public var style: TypedFieldStyle
    public var text: String
}

/// Everything the typed capture view shows: one plain text field and Save / Cancel.
@MainActor
public struct TypedCaptureScreen {
    public let title = "Type a capture"
    public let placeholder = "What is on your mind"
    public let fields: [TypedCaptureField]
    public let controls: [TypedCaptureControl]
    public let message: String?

    public init(model: TypedCaptureModel, text: String) {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        fields = [TypedCaptureField(style: .plain, text: text)]
        controls = [
            TypedCaptureControl(
                label: "Send", action: .save, isEnabled: !empty,
                disabledReason: empty ? "Type something first" : nil),
            TypedCaptureControl(label: "Cancel", action: .cancel, isEnabled: true, disabledReason: nil),
            TypedCaptureControl(label: "Record instead", action: .recordInstead, isEnabled: true, disabledReason: nil),
        ]
        message = model.message
    }
}
