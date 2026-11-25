import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Core

struct AttachmentPickerSheet: View {
    let onSelect: (CaptureAttachment) -> Void
    let onDismiss: () -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            photoRow
            filesRow
            clipboardRow
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Theme.amber)
                    .wrapping()
            }
            cancelButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(glow: .cyan)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            _Concurrency.Task { await loadPhoto(item) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private var header: some View {
        HStack {
            Text("Add Attachment")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Spacer()
            Text("Attaches with note")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var photoRow: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            AttachmentOptionRow(
                symbol: "photo.on.rectangle.angled",
                title: "Photo Library",
                subtitle: "Attach an image or screenshot",
                tint: Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private var filesRow: some View {
        Button {
            showingFileImporter = true
        } label: {
            AttachmentOptionRow(
                symbol: "doc.fill",
                title: "Files / PDF",
                subtitle: "Pick a document from Files",
                tint: Theme.emeraldApprove)
        }
        .buttonStyle(.plain)
    }

    private var clipboardRow: some View {
        Button {
            importFromClipboard()
        } label: {
            AttachmentOptionRow(
                symbol: "doc.on.clipboard",
                title: "Recent / Clipboard",
                subtitle: "Use copied screenshot or snippet",
                tint: Theme.glowCyan)
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button(action: onDismiss) {
            Text("Discard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                .background(Theme.glassBaseMid.opacity(0.72), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.primaryWhite.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        let data = try? await item.loadTransferable(type: Data.self)
        let suffix = item.itemIdentifier.map { String($0.prefix(8)) } ?? "photo"
        let attachment = CaptureAttachment(fileName: "IMG_\(suffix).heic", kind: .photo, byteCount: data?.count ?? 0)
        selectedPhoto = nil
        onSelect(attachment)
    }

    @MainActor
    private func handleFileImport(_ result: Swift.Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result { notice = "Could not open the selected file." }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let attachment = CaptureAttachment(fileName: url.lastPathComponent, kind: .file, byteCount: size)
        onSelect(attachment)
    }

    @MainActor
    private func importFromClipboard() {
        let board = UIPasteboard.general
        if let image = board.image, let data = image.pngData() {
            onSelect(CaptureAttachment(fileName: "Clipboard_Screenshot.png", kind: .screenshot, byteCount: data.count))
            return
        }
        if let text = board.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let bytes = text.data(using: .utf8)?.count ?? 0
            onSelect(CaptureAttachment(fileName: "Clipboard_Snippet.txt", kind: .file, byteCount: bytes))
            return
        }
        notice = "Clipboard has no image or text yet."
    }
}

private struct AttachmentOptionRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .liquidGlassCircle(tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .frame(minHeight: Theme.minimumTapTarget)
        .background(Theme.surfaceDeep.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.primaryWhite.opacity(0.12), lineWidth: 1)
        )
    }
}
