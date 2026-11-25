import SwiftUI

/// Top slide-down Obsidian Liquid Glass toast banner for transient decision/queue notices.
struct TransientToastBanner: View {
    let message: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText: String?
    @State private var presentationToken = 0

    var body: some View {
        Group {
            if let text = displayedText {
                toastCapsule(text)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: displayedText)
        .onAppear { syncMessage(message) }
        .onChange(of: message) { _, next in syncMessage(next) }
        .task(id: presentationToken) {
            guard displayedText != nil else { return }
            do { try await Task.sleep(for: .seconds(3.5)) } catch { return }
            dismiss()
        }
    }

    private func toastCapsule(_ text: String) -> some View {
        Button(action: dismiss) {
            HStack(spacing: 10) {
                Circle().fill(Theme.amber).frame(width: 8, height: 8)
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: Theme.minimumTapTarget)
            .background(glassFill)
            .overlay(glassStroke)
            .shadow(color: Theme.canvas.opacity(0.55), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Tap to dismiss")
    }

    private var glassFill: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Theme.glassBaseTop.opacity(0.16), Theme.glassBaseMid.opacity(0.82), Theme.glassBaseBottom.opacity(0.90)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var glassStroke: some View {
        Capsule().strokeBorder(
            LinearGradient(
                colors: [Theme.amber.opacity(0.55), Theme.primaryWhite.opacity(0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1)
    }

    private func syncMessage(_ raw: String?) {
        guard let raw else { displayedText = nil; return }
        let cleaned = Self.friendlyText(for: raw)
        guard !cleaned.isEmpty else { displayedText = nil; return }
        presentationToken += 1
        if reduceMotion { displayedText = cleaned }
        else { withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { displayedText = cleaned } }
    }

    private func dismiss() {
        if reduceMotion { displayedText = nil }
        else { withAnimation(.easeOut(duration: 0.2)) { displayedText = nil } }
    }

    static func friendlyText(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("open queue")
            || (lower.contains("only") && lower.contains("open") && (lower.contains("dropped") || lower.contains("rejected")))
            || lower.contains("suggestion is rejected")
            || lower.contains("422") {
            return "Already updated — refreshing your queue."
        }
        return trimmed
    }
}
