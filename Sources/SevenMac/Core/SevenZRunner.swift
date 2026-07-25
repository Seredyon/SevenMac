import Foundation
import Darwin

struct SevenZResult {
    let status: Int32
    let output: String
}

enum SevenZError: LocalizedError {
    case binaryMissing
    case needsPassword
    case cancelled
    case failed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "The 7zz command line tool could not be found. Set its location in Settings."
        case .needsPassword:
            return "This archive is encrypted. A password is required."
        case .cancelled:
            return "The operation was cancelled."
        case let .failed(status, output):
            return "7-Zip exited with code \(status).\n\n\(SevenZRunner.summarizeFailure(output))"
        }
    }
}

/// Thin, synchronous wrapper around the `7zz` executable.
/// Always call `run` from a background queue.
final class SevenZRunner {
    static let shared = SevenZRunner()

    var binaryPath: String = ""

    private init() {}

    var isAvailable: Bool { SevenZBinary.resolve(preferred: binaryPath) != nil }

    @discardableResult
    func run(_ arguments: [String],
             password: String? = nil,
             workingDirectory: URL? = nil,
             wantsProgress: Bool = false,
             onProcess: ((Process) -> Void)? = nil,
             onProgress: ((Double, String) -> Void)? = nil) throws -> SevenZResult {

        guard let binary = SevenZBinary.resolve(preferred: binaryPath) else {
            throw SevenZError.binaryMissing
        }

        var args = arguments
        args.append("-y")            // assume yes on queries
        args.append("-bse1")         // stderr -> stdout, single stream
        if wantsProgress { args.append("-bsp1") }
        if let password, !password.isEmpty {
            args.append("-p" + password)
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = args
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }

        let inPipe = Pipe()
        process.standardInput = inPipe

        // 7zz switches stdout to full buffering when it is connected to a pipe,
        // so live percentages arrive in rare large bursts (or only at the end).
        // Running it on a pseudo-terminal keeps it line-buffered and makes the
        // progress stream flow in real time. Fall back to a plain pipe if the
        // PTY cannot be created.
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var outPipe: Pipe?

        if wantsProgress, openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 {
            let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
            process.standardOutput = slaveHandle
            process.standardError = slaveHandle
        } else {
            masterFD = -1
            let pipe = Pipe()
            outPipe = pipe
            process.standardOutput = pipe
            process.standardError = pipe
        }

        try process.run()
        onProcess?(process)
        // Close stdin immediately so 7zz never blocks on an interactive prompt.
        inPipe.fileHandleForWriting.closeFile()

        var collected = Data()

        if masterFD >= 0 {
            // Parent must close its copy of the slave end, otherwise read()
            // below would never see EOF.
            close(slaveFD)
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(masterFD, &buffer, buffer.count)
                if n <= 0 { break }   // 0 = EOF, -1/EIO = child exited
                let chunk = Data(buffer[0..<n])
                collected.append(chunk)
                if let onProgress,
                   let parsed = Self.parseProgress(String(decoding: chunk, as: UTF8.self)) {
                    onProgress(parsed.0, parsed.1)
                }
            }
            close(masterFD)
        } else if let outPipe {
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
                if let onProgress,
                   let parsed = Self.parseProgress(String(decoding: chunk, as: UTF8.self)) {
                    onProgress(parsed.0, parsed.1)
                }
            }
        }
        process.waitUntilExit()

        let output = String(decoding: collected, as: UTF8.self)
        let status = process.terminationStatus

        if status != 0 {
            // 255 is 7-Zip's "user stopped the process" code; SIGTERM from Cancel
            // also surfaces as an uncaught-signal termination.
            if status == 255 || process.terminationReason == .uncaughtSignal {
                throw SevenZError.cancelled
            }
            if Self.looksLikePasswordProblem(output) { throw SevenZError.needsPassword }
            throw SevenZError.failed(status: status, output: output)
        }
        return SevenZResult(status: status, output: Self.cleanOutput(output))
    }

    static func looksLikePasswordProblem(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("wrong password")
            || lowered.contains("cannot open encrypted archive")
            || lowered.contains("enter password")
    }

    /// Collapses `\r` / backspace progress spam so logs and reports stay readable.
    static func cleanOutput(_ output: String) -> String {
        output
            // Drop ANSI escape sequences that 7zz may emit on a terminal.
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            // A PTY terminates every line with \r\n; normalize that first so the
            // carriage-return collapse below never wipes out real content.
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{08}", with: "\r")
            .components(separatedBy: "\n")
            .map { line -> String in
                // Keep only the final state of every carriage-return updated line.
                line.components(separatedBy: "\r").last ?? line
            }
            .joined(separator: "\n")
    }

    /// Produces a short, human-sized failure summary that is safe to put in an alert.
    static func summarizeFailure(_ output: String) -> String {
        let normalized = output
            .replacingOccurrences(of: "\u{08}", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let meaningful = lines.filter { line in
            guard !line.isEmpty else { return false }
            if line.range(of: "^[0-9]{1,3}%", options: .regularExpression) != nil { return false }
            if line.range(of: "^[0-9]+M? Scan", options: .regularExpression) != nil { return false }
            if line.hasPrefix("Scanning the drive") { return false }
            if line.hasPrefix("+ ") || line.contains(" + ") { return false }
            return true
        }

        var tail = meaningful.suffix(6).joined(separator: "\n")
        if tail.count > 500 {
            tail = "\u{2026}" + String(tail.suffix(500))
        }
        return tail.isEmpty ? "See the full log for details." : tail
    }

    /// Parses lines such as `  37% 12 - some/file.txt` produced by `-bsp1`.
    static func parseProgress(_ text: String) -> (Double, String)? {
        // On a PTY 7zz overwrites the status line with backspaces as well as
        // carriage returns; treat both as line separators.
        let pieces = text
            .replacingOccurrences(of: "\u{08}", with: "\r")
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        for piece in pieces.reversed() {
            let line = piece.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "^[0-9]{1,3}%", options: .regularExpression) else { continue }
            let digits = line[range].dropLast()
            guard let value = Double(digits) else { continue }
            let detail = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return (min(max(value / 100.0, 0), 1), detail)
        }
        return nil
    }
}
