import SwiftUI
import AppKit

struct ArchiveEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let archive: URL
    let path: String
    let password: String
    var onSave: () -> Void
    @State private var document: ArchiveDocument?
    @State private var text = ""
    @State private var busy = true
    @State private var error: String?
    @State private var savedBackup: URL?
    @State private var confirmDiscard = false

    private var dirty: Bool { document?.text != nil && text != document?.text }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass").font(.title).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text((path as NSString).lastPathComponent).font(.headline)
                    Text(archive.lastPathComponent + " / " + path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if dirty { Text("Edited").font(.caption).foregroundStyle(.orange) }
                if let document { Text(document.canModify ? "Editable" : "Read only").font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
            Divider()
            if let notice = ArchiveService.modificationNotice(archive) {
                Label(notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.orange.opacity(0.08))
            }
            if let document, document.text != nil {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
                    .disabled(busy || !document.canModify)
                    .padding(10)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: busy ? "hourglass" : "doc.richtext").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text(busy ? "Reading file…" : "Binary or large file").font(.title3.weight(.semibold))
                    Text("The editor supports UTF-8 text up to 2 MB. Replace File keeps the original entry name and path.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
                    if let document { Text(Formatting.size(document.size)).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 20).padding(.bottom, 12) }
            if let backup = savedBackup {
                HStack {
                    Label("Saved and verified. Previous version kept as a backup.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Show Backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                }.font(.callout).padding(12)
            }
            Divider()
            HStack {
                if busy { ProgressView().controlSize(.small); Text("Please wait…").foregroundStyle(.secondary) }
                else if let document, document.text != nil { Text("UTF-8 · \(text.utf8.count) bytes").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Close") { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(busy)
                Button("Replace File…") { chooseReplacement() }.disabled(busy || document?.canModify != true)
                Button("Save to Archive") { save(replacement: nil) }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !dirty || document?.canModify != true)
            }.padding(16)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 620)
        .interactiveDismissDisabled(busy || dirty)
        .alert("Discard unsaved changes?", isPresented: $confirmDiscard) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        }
        .onAppear { load() }
    }

    private func load() {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ArchiveEditor.load(archive: archive, path: path, password: password) }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case let .success(value): document = value; text = value.text ?? ""
                case let .failure(value): error = value.localizedDescription
                }
            }
        }
    }

    private func chooseReplacement() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Replace \(path) inside \(archive.lastPathComponent). A backup of the original archive will be kept."
        if panel.runModal() == .OK, let url = panel.url { save(replacement: url) }
    }

    private func save(replacement: URL?) {
        guard let document else { return }
        let content = text
        busy = true; error = nil; savedBackup = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ArchiveEditor.save(document, replacement: replacement, text: content) }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case let .success(backup): savedBackup = backup; onSave(); load()
                case let .failure(value): error = value.localizedDescription
                }
            }
        }
    }
}
