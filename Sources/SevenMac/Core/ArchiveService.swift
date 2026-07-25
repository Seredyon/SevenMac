import Foundation

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZip = "7z"
    case zip
    case tar
    case gzip
    case bzip2
    case xz
    case wim

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .gzip: return "GZIP"
        case .bzip2: return "BZIP2"
        case .xz: return "XZ"
        case .wim: return "WIM"
        }
    }

    var fileExtension: String { rawValue }

    var supportsEncryption: Bool { self == .sevenZip || self == .zip }
    var supportsHeaderEncryption: Bool { self == .sevenZip }
    var supportsSolid: Bool { self == .sevenZip }
}

enum CompressionLevel: Int, CaseIterable, Identifiable {
    case store = 0
    case fastest = 1
    case fast = 3
    case normal = 5
    case maximum = 7
    case ultra = 9

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .store: return "Store (0)"
        case .fastest: return "Fastest (1)"
        case .fast: return "Fast (3)"
        case .normal: return "Normal (5)"
        case .maximum: return "Maximum (7)"
        case .ultra: return "Ultra (9)"
        }
    }
}

enum OverwriteMode: String, CaseIterable, Identifiable {
    case overwrite
    case skip
    case renameNew
    case renameExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite: return "Overwrite existing files"
        case .skip: return "Skip existing files"
        case .renameNew: return "Auto rename extracted files"
        case .renameExisting: return "Auto rename existing files"
        }
    }

    var switchValue: String {
        switch self {
        case .overwrite: return "-aoa"
        case .skip: return "-aos"
        case .renameNew: return "-aou"
        case .renameExisting: return "-aot"
        }
    }
}

struct AddOptions {
    var format: ArchiveFormat = .sevenZip
    var level: CompressionLevel = .normal
    var password: String = ""
    var encryptHeaders: Bool = true
    var solid: Bool = true
    var volumeSize: String = ""          // e.g. "100m", empty = single file
    var threads: Int = 0                  // 0 = automatic
    var deleteSourceAfter: Bool = false
}

struct ExtractOptions {
    var destination: URL
    var keepFullPaths: Bool = true
    var overwrite: OverwriteMode = .renameNew
    var password: String = ""
    var selectedPaths: [String] = []
}

enum HashAlgorithm: String, CaseIterable, Identifiable {
    case crc32 = "CRC32"
    case crc64 = "CRC64"
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case blake2sp = "BLAKE2SP"
    var id: String { rawValue }
}

/// Builds and executes 7zz command lines.
enum ArchiveService {

    static let archiveExtensions: Set<String> = [
        "7z", "zip", "zipx", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz",
        "lzma", "lz4", "zst", "cab", "iso", "dmg", "wim", "msi", "exe", "apk", "ipa",
        "jar", "war", "epub", "cpio", "rpm", "deb", "arj", "lzh", "chm", "vhd", "xar", "pkg"
    ]

    static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if archiveExtensions.contains(ext) { return true }
        // Split volumes produced by 7-Zip's -v switch: archive.7z.001, .002, ...
        if isVolumeSuffix(ext) {
            return archiveExtensions.contains(url.deletingPathExtension().pathExtension.lowercased())
        }
        // RAR / ZIP style volumes: archive.r00, archive.z01
        if ext.count == 3, ext.first == "r" || ext.first == "z",
           ext.dropFirst().allSatisfy({ $0.isNumber }) {
            return true
        }
        return false
    }

    /// True for purely numeric split-volume suffixes such as "001".
    static func isVolumeSuffix(_ ext: String) -> Bool {
        ext.count >= 2 && ext.count <= 4 && ext.allSatisfy { $0.isNumber }
    }

    /// Maps any volume of a split archive to its first volume - the one 7zz
    /// must be pointed at for list, extract and test operations.
    static func primaryVolume(_ url: URL) -> URL {
        let ext = url.pathExtension
        guard isVolumeSuffix(ext.lowercased()), Int(ext) != 1 else { return url }
        let first = url.deletingPathExtension()
            .appendingPathExtension(String(format: "%0\(ext.count)d", 1))
        return FileManager.default.fileExists(atPath: first.path) ? first : url
    }

    // MARK: - Listing

    static func list(archive: URL, password: String) throws -> (entries: [ArchiveEntry], summary: ArchiveSummary) {
        let result = try SevenZRunner.shared.run(
            ["l", "-slt", "-sccUTF-8", archive.path],
            password: password
        )
        return ArchiveListParser.parse(result.output)
    }

    // MARK: - Command builders

    /// Validates split-volume sizes such as `100m`, `4g`, `700k`, `65536b`.
    static func isValidVolumeSize(_ value: String) -> Bool {
        value.range(of: "^[0-9]+[bkmgBKMG]?$", options: .regularExpression) != nil
    }

    static func addArguments(archive: URL, inputPaths: [String], options: AddOptions) -> [String] {
        var args = ["a", "-t" + options.format.rawValue, "-mx=\(options.level.rawValue)"]

        if options.threads > 0 { args.append("-mmt=\(options.threads)") }
        if options.format.supportsSolid {
            args.append(options.solid ? "-ms=on" : "-ms=off")
        }
        if options.format.supportsHeaderEncryption, !options.password.isEmpty, options.encryptHeaders {
            args.append("-mhe=on")
        }
        if !options.volumeSize.isEmpty {
            args.append("-v" + options.volumeSize.lowercased())
        }
        if options.deleteSourceAfter { args.append("-sdel") }

        args.append(archive.path)
        args.append(contentsOf: inputPaths)
        return args
    }

    static func extractArguments(archive: URL, options: ExtractOptions) -> [String] {
        var args = [options.keepFullPaths ? "x" : "e"]
        args.append("-o" + options.destination.path)
        args.append(options.overwrite.switchValue)
        args.append("-sccUTF-8")
        args.append(archive.path)
        for path in options.selectedPaths {
            args.append(path)
        }
        return args
    }

    static func testArguments(archive: URL) -> [String] {
        ["t", archive.path]
    }

    static func deleteArguments(archive: URL, paths: [String]) -> [String] {
        ["d", archive.path] + paths
    }

    static func renameArguments(archive: URL, from: String, to: String) -> [String] {
        ["rn", archive.path, from, to]
    }

    static func hashArguments(paths: [URL], algorithm: HashAlgorithm) -> [String] {
        ["h", "-scrc" + algorithm.rawValue] + paths.map { $0.path }
    }

    static func benchmarkArguments(dictionary: String, passes: Int) -> [String] {
        var args = ["b"]
        if passes > 0 { args.append("\(passes)") }
        if !dictionary.isEmpty { args.append("-md=" + dictionary) }
        return args
    }

    /// Default archive URL suggested for a selection of files.
    static func suggestedArchiveURL(for inputs: [URL], format: ArchiveFormat) -> URL {
        guard let first = inputs.first else {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Archive." + format.fileExtension)
        }
        let folder = first.deletingLastPathComponent()
        let base: String
        if inputs.count == 1 {
            base = first.deletingPathExtension().lastPathComponent
        } else {
            base = folder.lastPathComponent.isEmpty ? "Archive" : folder.lastPathComponent
        }
        return folder.appendingPathComponent(base + "." + format.fileExtension)
    }
}
