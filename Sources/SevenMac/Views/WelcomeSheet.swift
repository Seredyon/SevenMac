import SwiftUI
import AppKit

/// One-time onboarding: explains what the app does and how to grant
/// Full Disk Access once instead of approving every folder separately.
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to SevenMac").font(.title2.weight(.semibold))
                    Text("The 7-Zip file manager for macOS")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                row(icon: "folder",
                    title: "Browse archives like folders",
                    text: "Double-click any archive to step inside it. Add, extract, test and checksum from the toolbar.")
                row(icon: "lock.open",
                    title: "Give access once, not per folder",
                    text: "macOS asks permission for Desktop, Documents and Downloads separately. To avoid these prompts, add SevenMac to Full Disk Access in System Settings \u{2192} Privacy & Security. This is a one-time step and can be reverted at any time.")
                row(icon: "bolt",
                    title: "Powered by the official 7-Zip engine",
                    text: "Every operation runs the bundled 7zz binary \u{2014} the same engine as 7-Zip on Windows.")
            }
            .padding(20)

            Divider()

            HStack {
                Button {
                    openFullDiskAccessSettings()
                } label: {
                    Label("Open Full Disk Access Settings", systemImage: "gearshape")
                }
                Spacer()
                Button("Get Started") {
                    onDone()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 560)
    }

    private func row(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

func openFullDiskAccessSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        NSWorkspace.shared.open(url)
    }
}
