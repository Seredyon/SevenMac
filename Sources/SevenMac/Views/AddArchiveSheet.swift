import SwiftUI
import AppKit

struct AddArchiveSheet: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let inputs: [URL]
    var onStart: (URL, AddOptions) -> Void

    @State private var options = AddOptions()
    @State private var archiveURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Archive.7z")
    @State private var confirmPassword = ""
    @State private var splitEnabled = false

    private var passwordsMatch: Bool {
        options.password.isEmpty || options.password == confirmPassword
    }

    private var volumeSizeOK: Bool {
        !splitEnabled || ArchiveService.isValidVolumeSize(options.volumeSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Add to Archive",
                        subtitle: inputs.count == 1
                            ? inputs[0].lastPathComponent
                            : "\(inputs.count) items")

            Form {
                Section {
                    LabeledContent("Archive") {
                        HStack {
                            Text(archiveURL.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button("Choose\u{2026}") { chooseDestination() }
                        }
                    }
                    LabeledContent("Folder") {
                        Text(archiveURL.deletingLastPathComponent().path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Compression") {
                    Picker("Format", selection: $options.format) {
                        ForEach(ArchiveFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Picker("Level", selection: $options.level) {
                        ForEach(CompressionLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    if options.format.supportsSolid {
                        Toggle("Solid archive", isOn: $options.solid)
                    }
                    Picker("CPU threads", selection: $options.threads) {
                        Text("Automatic").tag(0)
                        ForEach([1, 2, 4, 8, 10, 12, 16], id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                }

                Section("Encryption") {
                    if options.format.supportsEncryption {
                        SecureField("Password", text: $options.password)
                        SecureField("Repeat password", text: $confirmPassword)
                        if options.format.supportsHeaderEncryption {
                            Toggle("Encrypt file names (AES-256)", isOn: $options.encryptHeaders)
                                .disabled(options.password.isEmpty)
                        }
                        if !passwordsMatch {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("\(options.format.displayName) does not support encryption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Options") {
                    Toggle("Split into volumes", isOn: $splitEnabled)
                    if splitEnabled {
                        TextField("Volume size", text: $options.volumeSize, prompt: Text("e.g. 100m, 700m, 4g"))
                        if !volumeSizeOK {
                            Text("Enter a number with an optional unit: b, k, m or g (example: 100m).")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("The archive will be written as .7z.001, .7z.002, \u{2026}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Delete files after compression", isOn: $options.deleteSourceAfter)
                }
            }
            .formStyle(.grouped)

            SheetFooter(confirmTitle: "Compress",
                        confirmDisabled: !passwordsMatch || !volumeSizeOK,
                        onCancel: { dismiss() },
                        onConfirm: {
                            if !splitEnabled { options.volumeSize = "" }
                            onStart(archiveURL, options)
                            dismiss()
                        })
        }
        .frame(width: 520, height: 620)
        .onAppear {
            options.format = settings.format
            options.level = settings.level
            archiveURL = ArchiveService.suggestedArchiveURL(for: inputs, format: options.format)
        }
        .onChange(of: options.format) { newFormat in
            archiveURL = archiveURL
                .deletingPathExtension()
                .appendingPathExtension(newFormat.fileExtension)
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = archiveURL.lastPathComponent
        panel.directoryURL = archiveURL.deletingLastPathComponent()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            archiveURL = url
        }
    }
}

struct SheetHeader: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

struct SheetFooter: View {
    var confirmTitle: String
    var confirmDisabled: Bool = false
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle, action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(confirmDisabled)
        }
        .padding(20)
    }
}
