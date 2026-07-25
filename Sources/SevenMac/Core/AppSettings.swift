import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var customBinaryPath: String {
        didSet {
            defaults.set(customBinaryPath, forKey: "customBinaryPath")
            SevenZRunner.shared.binaryPath = customBinaryPath
        }
    }
    @Published var defaultFormat: String {
        didSet { defaults.set(defaultFormat, forKey: "defaultFormat") }
    }
    @Published var defaultLevel: Int {
        didSet { defaults.set(defaultLevel, forKey: "defaultLevel") }
    }
    @Published var showHiddenFiles: Bool {
        didSet { defaults.set(showHiddenFiles, forKey: "showHiddenFiles") }
    }
    @Published var revealAfterExtract: Bool {
        didSet { defaults.set(revealAfterExtract, forKey: "revealAfterExtract") }
    }
    @Published var didShowWelcome: Bool {
        didSet { defaults.set(didShowWelcome, forKey: "didShowWelcome") }
    }

    init() {
        customBinaryPath = defaults.string(forKey: "customBinaryPath") ?? ""
        defaultFormat = defaults.string(forKey: "defaultFormat") ?? ArchiveFormat.sevenZip.rawValue
        defaultLevel = defaults.object(forKey: "defaultLevel") as? Int ?? CompressionLevel.normal.rawValue
        showHiddenFiles = defaults.object(forKey: "showHiddenFiles") as? Bool ?? false
        revealAfterExtract = defaults.object(forKey: "revealAfterExtract") as? Bool ?? true
        didShowWelcome = defaults.bool(forKey: "didShowWelcome")
    }

    var format: ArchiveFormat {
        ArchiveFormat(rawValue: defaultFormat) ?? .sevenZip
    }

    var level: CompressionLevel {
        CompressionLevel(rawValue: defaultLevel) ?? .normal
    }
}

enum Formatting {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func size(_ value: Int64) -> String {
        value <= 0 ? "\u{2014}" : byteFormatter.string(fromByteCount: value)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func date(_ value: Date?) -> String {
        guard let value else { return "\u{2014}" }
        return dateFormatter.string(from: value)
    }

    static func percent(_ value: Double) -> String {
        guard value > 0 else { return "\u{2014}" }
        return String(format: "%.0f%%", value * 100)
    }
}
