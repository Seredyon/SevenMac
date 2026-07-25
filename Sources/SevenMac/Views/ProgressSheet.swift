import SwiftUI

struct ProgressSheet: View {
    @EnvironmentObject var job: JobRunner

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(job.title)
                    .font(.headline)

                if job.indeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: job.fraction)
                        .progressViewStyle(.linear)
                }

                HStack {
                    Text(job.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(job.indeterminate ? "" : String(format: "%.0f%%", job.fraction * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { job.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(22)
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 22, y: 8)
        }
    }
}

struct TextReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: title)
            ScrollView {
                Text(text.isEmpty ? "No output" : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 640, height: 480)
    }
}
