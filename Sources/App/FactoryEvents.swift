import Foundation

/// The factory's development event log (D-20261126-p-66, issue #88). The factory owns this file and writes it back at
/// every run: call it, never edit it.
///
/// Call `FactoryEvents.log("spoke", word)` once per user-relevant event: a text the app spoke, a sound it played
/// (`"played"`, sound name), progress it saved (`"saved"`, what), a round it finished (`"finished"`, which). The text
/// names what the app did, never what the user typed or who the user is, and never holds audio. In a DEBUG build
/// the call appends one line, `<UTC time> <event> <text>`, to `Library/Caches/factory-events/events.log` in the app's
/// own container, where the journey player reads it. In a release build the call does nothing and nothing of the log
/// is compiled in.
enum FactoryEvents {
    #if DEBUG
    private static let queue = DispatchQueue(label: "factory-events")

    static func log(_ event: StaticString, _ text: String = "") {
        let name = event.description.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        let clean = String(text.map { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true ? " " : $0 }
            .prefix(80))
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "\(stamp.string(from: Date())) \(String(name.prefix(32))) \(clean)\n"
        queue.sync { append(Data(line.utf8)) }
    }

    private static func append(_ data: Data) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let folder = caches.appendingPathComponent("factory-events", isDirectory: true)
        let file = folder.appendingPathComponent("events.log")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file, options: .atomic)
        }
    }
    #else
    @inline(__always) static func log(_ event: StaticString, _ text: String = "") {}
    #endif
}
