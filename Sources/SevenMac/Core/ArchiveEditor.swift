import Foundation
import CryptoKit
import Darwin

struct ArchiveEditError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ArchiveDocument {
    let archive: URL
    let path: String
    let fingerprint: String
    let type: String
    let text: String?
    let size: Int64
    let password: String
    var canModify: Bool { ArchiveService.canModify(archive, type: type) }
}

/// Every mutation is tested on a sibling copy before a single atomic rename.
/// A unique backup is retained next to the original, including for package files.
enum ArchiveEditor {
    static let textLimit: Int64 = 2 * 1024 * 1024

    static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("\n"), !path.contains("\r"), !path.contains("\0"),
              !path.hasPrefix("@"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ArchiveEditError(message: "This entry has an unsafe or ambiguous path and cannot be edited.")
        }
    }

    static func fingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func load(archive: URL, path: String, password: String) throws -> ArchiveDocument {
        try validatePath(path)
        let stamp = try fingerprint(archive)
        let listing = try ArchiveService.list(archive: archive, password: password)
        let matches = listing.entries.filter { $0.path == path }
        guard matches.count == 1, let entry = matches.first, !entry.isDirectory else {
            throw ArchiveEditError(message: "Select one regular file. Duplicate entry names cannot be edited safely.")
        }
        if entry.encrypted && password.isEmpty { throw SevenZError.needsPassword }
        var text: String?
        // Text is extracted to stdout, never to archive-controlled filesystem paths.
        if entry.size <= textLimit {
            let data = try readEntry(archive: archive, path: path, password: password)
            if !data.contains(0), let decoded = String(data: data, encoding: .utf8),
               !decoded.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) {
                text = decoded
            }
        }
        guard try fingerprint(archive) == stamp else { throw changedError }
        return ArchiveDocument(archive: archive, path: path, fingerprint: stamp,
                               type: listing.summary.type, text: text, size: entry.size, password: password)
    }

    private static var changedError: ArchiveEditError {
        ArchiveEditError(message: "The archive changed since it was opened. Close the editor and reopen the file before saving.")
    }

    static func readEntry(archive: URL, path: String, password: String) throws -> Data {
        guard let binary = SevenZBinary.resolve(preferred: SevenZRunner.shared.binaryPath) else { throw SevenZError.binaryMissing }
        let process = Process()
        process.executableURL = binary
        var args = ["x", "-so", "-spd", "-y", "-bso0", "-bsp0"]
        if !password.isEmpty { args.append("-p" + password) }
        args += ["--", archive.path, path]
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > textLimit {
                process.terminate()
                output.fileHandleForReading.closeFile()
                process.waitUntilExit()
                throw ArchiveEditError(message: "This file exceeds the 2 MB text editor limit. Use Replace File instead.")
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ArchiveEditError(message: "Could not read this file. For encrypted archives, use Unlock and enter the password first.")
        }
        return data
    }

    @discardableResult
    static func save(_ document: ArchiveDocument, replacement: URL? = nil, text: String? = nil) throws -> URL {
        guard document.canModify else { throw ArchiveEditError(message: "This archive format is read-only.") }
        try validatePath(document.path)
        return try transaction(archive: document.archive, expected: document.fingerprint, password: document.password) { staged in
            let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workspace) }
            let file = workspace.appendingPathComponent(document.path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let replacement {
                let values = try replacement.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw ArchiveEditError(message: "Choose a regular file to replace this entry.")
                }
                try FileManager.default.copyItem(at: replacement, to: file)
            } else if let text {
                try Data(text.utf8).write(to: file)
            } else { throw ArchiveEditError(message: "No replacement content was provided.") }
            // Remove first so same-size content with the same timestamp is still replaced.
            try SevenZRunner.shared.run(["d", "-t" + document.type.lowercased(), "-spd", "--", staged.path, document.path], password: document.password)
            var args = ["a", "-t" + document.type.lowercased(), "-spd"]
            if document.type.lowercased() == "zip", !document.password.isEmpty { args.append("-mem=AES256") }
            if document.type.lowercased() == "7z", !document.password.isEmpty { args.append("-mhe=on") }
            args += ["--", staged.path, document.path]
            try SevenZRunner.shared.run(args, password: document.password, workingDirectory: workspace)
        }
    }

    @discardableResult
    static func remove(archive: URL, paths: [String], password: String) throws -> URL {
        guard !paths.isEmpty else { throw ArchiveEditError(message: "Select files to remove.") }
        let stamp = try fingerprint(archive)
        let listing = try ArchiveService.list(archive: archive, password: password)
        guard ArchiveService.canModify(archive, type: listing.summary.type) else {
            throw ArchiveEditError(message: "This archive format is read-only.")
        }
        for path in paths { try validatePath(path) }
        return try transaction(archive: archive, expected: stamp, password: password) { staged in
            try SevenZRunner.shared.run(["d", "-t" + listing.summary.type.lowercased(), "-spd", "--", staged.path] + paths, password: password)
        }
    }

    private static func transaction(archive: URL, expected: String, password: String, mutate: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        let values = try archive.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ArchiveEditError(message: "Open the original archive file, rather than a symbolic link, to make changes.")
        }
        guard try fingerprint(archive) == expected else { throw changedError }
        let stagingFolder = archive.deletingLastPathComponent().appendingPathComponent(".sevenmac-" + UUID().uuidString)
        try fm.createDirectory(at: stagingFolder, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stagingFolder) }
        let staged = stagingFolder.appendingPathComponent(archive.lastPathComponent)
        try fm.copyItem(at: archive, to: staged)
        try mutate(staged)
        try SevenZRunner.shared.run(ArchiveService.testArguments(archive: staged), password: password)
        guard try fingerprint(archive) == expected else { throw changedError }
        let backup = archive.appendingPathExtension("backup-" + UUID().uuidString.prefix(8))
        try fm.copyItem(at: archive, to: backup)
        guard try fingerprint(archive) == expected else { throw changedError }
        guard Darwin.rename(staged.path, archive.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return backup
    }
}
