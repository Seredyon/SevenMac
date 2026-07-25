import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            engine.tabItem { Label("Engine", systemImage: "cpu") }
        }
        .frame(width: 480, height: 320)
    }

    private var general: some View {
        Form {
            Picker("Default format", selection: $settings.defaultFormat) {
                ForEach(ArchiveFormat.allCases) { format in
                    Text(format.displayName).tag(format.rawValue)
                }
            }
            Picker("Default level", selection: $settings.defaultLevel) {
                ForEach(CompressionLevel.allCases) { level in
                    Text(level.title).tag(level.rawValue)
                }
            }
            Toggle("Show hidden files", isOn: $settings.showHiddenFiles)
            Toggle("Reveal results in Finder", isOn: $settings.revealAfterExtract)

            Section("File access") {
                Text("macOS asks for permission per folder (Desktop, Documents, Downloads, \u{2026}). To grant access to everything once, add SevenMac to Full Disk Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    openFullDiskAccessSettings()
                } label: {
                    Label("Open Full Disk Access Settings", systemImage: "lock.open")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var engine: some View {
        Form {
            LabeledContent("7zz binary") {
                HStack {
                    Text(SevenZBinary.resolve(preferred: settings.customBinaryPath)?.path ?? "not found")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose\u{2026}") { choose() }
                    Button("Reset") { settings.customBinaryPath = "" }
                }
            }
            LabeledContent("Version", value: SevenZBinary.version(preferred: settings.customBinaryPath))
            Text("SevenMac ships with the official 7-Zip console binary (7zz) inside the app bundle. Point it somewhere else only if you keep your own build.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.customBinaryPath = url.path
        }
    }
}
