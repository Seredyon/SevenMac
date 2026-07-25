import Foundation

struct ArchiveEntry: Hashable {
    var path: String = ""
    var isDirectory: Bool = false
    var size: Int64 = 0
    var packedSize: Int64 = 0
    var modified: Date?
    var attributes: String = ""
    var crc: String = ""
    var method: String = ""
    var encrypted: Bool = false

    var components: [String] {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
    }
}

struct ArchiveSummary {
    var type: String = ""
    var physicalSize: Int64 = 0
    var totalSize: Int64 = 0
    var packedSize: Int64 = 0
    var fileCount: Int = 0
    var folderCount: Int = 0
    var isEncrypted: Bool = false
    var solid: String = ""
    var method: String = ""

    var ratio: Double {
        guard totalSize > 0 else { return 0 }
        return Double(packedSize) / Double(totalSize)
    }
}

/// Parses the output of `7zz l -slt`.
enum ArchiveListParser {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func parse(_ output: String) -> (entries: [ArchiveEntry], summary: ArchiveSummary) {
        var entries: [ArchiveEntry] = []
        var summary = ArchiveSummary()

        var reachedEntries = false
        var current = ArchiveEntry()
        var hasCurrent = false

        func flush() {
            if hasCurrent && !current.path.isEmpty {
                entries.append(current)
            }
            current = ArchiveEntry()
            hasCurrent = false
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("----------") {
                reachedEntries = true
                continue
            }
            if line.isEmpty {
                if reachedEntries { flush() }
                continue
            }

            guard let separator = line.range(of: " = ") else { continue }
            let key = String(line[line.startIndex..<separator.lowerBound])
            let value = String(line[separator.upperBound...])

            if !reachedEntries {
                switch key {
                case "Type": summary.type = value
                case "Physical Size": summary.physicalSize = Int64(value) ?? 0
                case "Solid": summary.solid = value
                case "Method": summary.method = value
                default: break
                }
                continue
            }

            hasCurrent = true
            switch key {
            case "Path": current.path = value.replacingOccurrences(of: "\\", with: "/")
            case "Size": current.size = Int64(value) ?? 0
            case "Packed Size": current.packedSize = Int64(value) ?? 0
            case "Modified": current.modified = dateFormatter.date(from: String(value.prefix(19)))
            case "Attributes":
                current.attributes = value
                if value.hasPrefix("D") { current.isDirectory = true }
            case "Folder": current.isDirectory = (value == "+")
            case "CRC": current.crc = value
            case "Method": current.method = value
            case "Encrypted": current.encrypted = (value == "+")
            default: break
            }
        }
        flush()

        for entry in entries {
            if entry.isDirectory {
                summary.folderCount += 1
            } else {
                summary.fileCount += 1
                summary.totalSize += entry.size
                summary.packedSize += entry.packedSize
            }
            if entry.encrypted { summary.isEncrypted = true }
        }
        if summary.packedSize == 0 { summary.packedSize = summary.physicalSize }
        return (entries, summary)
    }
}
