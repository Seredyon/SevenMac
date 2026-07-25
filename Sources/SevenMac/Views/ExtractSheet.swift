import SwiftUI
import AppKit

struct ExtractSheet: View {
    @Environment(\.dismiss) private var dismiss

    let archiveName: String
    let suggestedDestination: URL
    let selectedPaths: [String]
    let requiresPassword: Bool
    var onStart: (ExtractOptions) -> Void

    @State private var destination: URL = URL(fileURLWithPath: NSHomeDirectory())
    @State private var keepFullPaths = true
    @State private var overwrite: OverwriteMode = .renameNew
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Extract", subtitle: archiveName)

            Form {
                Section("Destination") {
                    LabeledContent("Folder") {
                        HStack {
                            Text(destination.path)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Button("Choose\u{2026}") { chooseFolder() }
                        }
                    }
                }

                Section("Options") {
                    Toggle("Keep folder structure", isOn: $keepFullPaths)
                    Picker("If a file exists", selection: $overwrite) {
                        ForEach(OverwriteMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    if !selectedPaths.isEmpty {
                        LabeledContent("Scope") {
                            Text("\(selectedPaths.count) selected item(s)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if requiresPassword {
                    Section("Encryption") {
                        SecureField("Password", text: $password)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter(confirmTitle: "Extract",
                        onCancel: { dismiss() },
                        onConfirm: {
                            onStart(ExtractOptions(destination: destination,
                                                   keepFullPaths: keepFullPaths,
                                                   overwrite: overwrite,
                                                   password: password,
                                                   selectedPaths: selectedPaths))
                            dismiss()
                        })
        }
        .frame(width: 520, height: 430)
        .onAppear { destination = suggestedDestination }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }
}

struct PasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    let archiveName: String
    var onSubmit: (String) -> Void
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Password required", subtitle: archiveName)
            Form {
                SecureField("Password", text: $password)
                    .onSubmit { submit() }
            }
            .formStyle(.grouped)
            SheetFooter(confirmTitle: "Unlock",
                        confirmDisabled: password.isEmpty,
                        onCancel: { dismiss() },
                        onConfirm: { submit() })
        }
        .frame(width: 420, height: 220)
    }

    private func submit() {
        onSubmit(password)
        dismiss()
    }
}
