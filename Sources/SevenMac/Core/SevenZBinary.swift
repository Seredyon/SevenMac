import Foundation

/// Locates the `7zz` command line binary that powers the app.
///
/// Search order:
/// 1. A user supplied path (Settings).
/// 2. The copy bundled inside `SevenMac.app/Contents/Resources/bin/7zz`.
/// 3. Common Homebrew / MacPorts locations.
enum SevenZBinary {
    static let fallbackPaths = [
        "/opt/homebrew/bin/7zz",
        "/usr/local/bin/7zz",
        "/opt/homebrew/bin/7z",
        "/usr/local/bin/7z",
        "/opt/local/bin/7zz"
    ]

    static func resolve(preferred: String?) -> URL? {
        let fm = FileManager.default

        if let preferred, !preferred.isEmpty, fm.isExecutableFile(atPath: preferred) {
            return URL(fileURLWithPath: preferred)
        }

        if let bundled = Bundle.main.url(forResource: "7zz", withExtension: nil, subdirectory: "bin"),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let sibling = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin/7zz")
        if fm.isExecutableFile(atPath: sibling.path) { return sibling }

        for path in fallbackPaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func version(preferred: String?) -> String {
        guard let url = resolve(preferred: preferred) else { return "7zz not found" }
        let process = Process()
        process.executableURL = url
        process.arguments = ["i"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "7zz not runnable"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? url.path : firstLine
    }
}
