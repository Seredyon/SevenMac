import SwiftUI

struct BenchmarkView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var dictionary = "32m"
    @State private var passes = 3
    @State private var output = ""
    @State private var running = false

    private let dictionaries = ["1m", "4m", "16m", "32m", "64m", "128m"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Benchmark",
                        subtitle: "LZMA compression and decompression rating for this Mac")

            Form {
                Picker("Dictionary size", selection: $dictionary) {
                    ForEach(dictionaries, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Stepper("Passes: \(passes)", value: $passes, in: 1...10)
            }
            .formStyle(.grouped)

            ScrollView {
                Text(output.isEmpty ? "Press Run to start." : output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor))

            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }
                Button(running ? "Running\u{2026}" : "Run") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
            }
            .padding(16)
        }
        .frame(width: 640, height: 560)
    }

    private func run() {
        running = true
        output = ""
        let args = ArchiveService.benchmarkArguments(dictionary: dictionary, passes: passes)
        DispatchQueue.global(qos: .userInitiated).async {
            var text: String
            do {
                text = try SevenZRunner.shared.run(args).output
            } catch {
                text = error.localizedDescription
            }
            let final = text
            DispatchQueue.main.async {
                output = final
                running = false
            }
        }
    }
}

struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let location: Location
    let summary: ArchiveSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Information", subtitle: location.title)

            Form {
                Section("Location") {
                    LabeledContent("Path") {
                        Text(location.displayPath)
                            .lineLimit(2)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                    }
                }
                if let summary {
                    Section("Archive") {
                        LabeledContent("Format", value: summary.type.isEmpty ? "\u{2014}" : summary.type)
                        LabeledContent("Files", value: "\(summary.fileCount)")
                        LabeledContent("Folders", value: "\(summary.folderCount)")
                        LabeledContent("Unpacked size", value: Formatting.size(summary.totalSize))
                        LabeledContent("Packed size", value: Formatting.size(summary.packedSize))
                        LabeledContent("Ratio", value: Formatting.percent(summary.ratio))
                        LabeledContent("Encrypted", value: summary.isEncrypted ? "Yes" : "No")
                        if !summary.method.isEmpty {
                            LabeledContent("Method", value: summary.method)
                        }
                        if !summary.solid.isEmpty {
                            LabeledContent("Solid", value: summary.solid)
                        }
                    }
                }
                Section("Engine") {
                    LabeledContent("7-Zip", value: SevenZBinary.version(preferred: SevenZRunner.shared.binaryPath))
                    LabeledContent("Binary", value: SevenZBinary.resolve(preferred: SevenZRunner.shared.binaryPath)?.path ?? "not found")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }
}
