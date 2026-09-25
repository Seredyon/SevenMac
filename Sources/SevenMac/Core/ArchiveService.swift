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

    var fileExtension: String {
        switch self { case .gzip: return "gz"; case .bzip2: return "bz2"; default: return rawValue }
    }

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

    // Containers understood by the bundled 7zz, plus ZIP-based package formats.
    static let archiveExtensions: Set<String> = Set("""
        7z zip zipx rar tar gz gzip tgz tpz bz2 bzip2 tbz tbz2 xz txz
        lzma lzma86 zst tzst z taz cab iso dmg wim swm esd ppkg msi msp msm
        exe apk apks xapk aab ipa jar war ear aar jmod epub cbz cbr cb7 cbt
        xpi vsix nupkg whl egg docx docm xlsx xlsm pptx pptm odt ods odp
        ott ots otp odg pages numbers key appx appxbundle msix msixbundle
        cpio rpm deb udeb ar a arj lzh lha chm chi chq chw vhd vhdx avhdx
        vdi vmdk qcow qcow2 qcow2c xar pkg xip ova img apfs hfs hfsx
        ext ext2 ext3 ext4 fat ntfs squashfs cramfs udf simg lpimg
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static func canModify(_ archive: URL, type: String) -> Bool {
        ["zip", "7z", "tar"].contains(type.lowercased())
            && !isVolumeSuffix(archive.pathExtension)
            && archive.pathExtension.lowercased().range(of: "^(r|z)[0-9]{2}$", options: .regularExpression) == nil
    }

    static func modificationNotice(_ archive: URL) -> String? {
        switch archive.pathExtension.lowercased() {
        case "apk", "apks", "xapk", "aab", "ipa", "jar", "appx", "msix", "appxbundle", "msixbundle", "xpi":
            return "Changing this package invalidates its signature. Sign it again with the platform tools before installing or distributing it. Android binary XML, resources and DEX require dedicated tools; they can be replaced here."
        case "epub", "docx", "xlsx", "pptx", "odt", "ods", "odp", "pages", "numbers", "key":
            return "Keep the document’s internal structure intact. Archive integrity does not guarantee that the document will open in its original app."
        default: return nil
        }
    }

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
        let ext = url.pathExtension.lowercased()
        var first = url
        if isVolumeSuffix(ext), Int(ext) != 1 {
            first = url.deletingPathExtension().appendingPathExtension(String(format: "%0\(ext.count)d", 1))
        } else if ext.range(of: "^r[0-9]{2}$", options: .regularExpression) != nil {
            first = url.deletingPathExtension().appendingPathExtension("rar")
        } else if ext.range(of: "^z[0-9]{2}$", options: .regularExpression) != nil {
            first = url.deletingPathExtension().appendingPathExtension("zip")
        } else if let range = url.lastPathComponent.range(of: "(?i)\\.part[0-9]+\\.rar$", options: .regularExpression) {
            let suffix = String(url.lastPathComponent[range]).dropFirst(5).dropLast(4)
            let name = String(url.lastPathComponent[..<range.lowerBound]) + ".part" + String(format: "%0\(suffix.count)d", 1) + ".rar"
            first = url.deletingLastPathComponent().appendingPathComponent(name)
        }
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
            && (UInt64(value.prefix(while: { $0.isNumber })) ?? 0) > 0
    }

    static func addArguments(archive: URL, inputPaths: [String], options: AddOptions) -> [String] {
        var args = ["a", "-spd", "-t" + options.format.rawValue, "-mx=\(options.level.rawValue)"]

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

        if options.format == .zip, !options.password.isEmpty { args.append("-mem=AES256") }
        args.append("--")
        args.append(archive.path)
        args.append(contentsOf: inputPaths.map { $0.hasPrefix("/") ? $0 : "./" + $0 })
        return args
    }

    static func extractArguments(archive: URL, options: ExtractOptions) -> [String] {
        var args = [options.keepFullPaths ? "x" : "e"]
        args.append("-o" + options.destination.path)
        args.append(options.overwrite.switchValue)
        args.append("-sccUTF-8")
        args.append("-spd")
        args.append(contentsOf: options.selectedPaths.map { "-i!" + $0 })
        args.append("--")
        args.append(archive.path)
        return args
    }

    static func testArguments(archive: URL) -> [String] {
        ["t", archive.path]
    }

    static func deleteArguments(archive: URL, paths: [String]) -> [String] {
        ["d", "-spd", "--", archive.path] + paths
    }

    static func renameArguments(archive: URL, from: String, to: String) -> [String] {
        ["rn", "-spd", "--", archive.path, from, to]
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
