import Foundation
import SwiftUI

struct Item: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String            // absolute path in folder mode, inner path in archive mode
    var isDirectory: Bool
    var isArchive: Bool
    var size: Int64
    var packedSize: Int64
    var modified: Date?
    var attributes: String = ""
    var crc: String = ""
    var encrypted: Bool = false

    var kind: String {
        if isDirectory { return "Folder" }
        let ext = (name as NSString).pathExtension
        if isArchive {
            if !ext.isEmpty, ext.allSatisfy({ $0.isNumber }) {
                let baseExt = ((name as NSString).deletingPathExtension as NSString).pathExtension
                return (baseExt.isEmpty ? "Split" : baseExt.uppercased()) + " volume " + ext
            }
            return ext.isEmpty ? "Archive" : ext.uppercased() + " archive"
        }
        return ext.isEmpty ? "File" : ext.uppercased() + " file"
    }

    var ratio: Double {
        guard size > 0, packedSize > 0 else { return 0 }
        return Double(packedSize) / Double(size)
    }

    /// Sortable stand-in for the optional modification date.
    var modifiedTimestamp: TimeInterval { modified?.timeIntervalSince1970 ?? 0 }
}

enum Location: Hashable {
    case folder(URL)
    case archive(archive: URL, inner: String)

    var isArchive: Bool {
        if case .archive = self { return true }
        return false
    }

    var displayPath: String {
        switch self {
        case let .folder(url):
            return url.path
        case let .archive(archive, inner):
            return inner.isEmpty ? archive.path : archive.path + "/" + inner
        }
    }

    var title: String {
        switch self {
        case let .folder(url):
            return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        case let .archive(archive, inner):
            return inner.isEmpty ? archive.lastPathComponent : (inner as NSString).lastPathComponent
        }
    }
}

final class BrowserModel: ObservableObject {
    @Published private(set) var location: Location
    @Published private(set) var items: [Item] = []
    @Published private(set) var summary: ArchiveSummary?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var needsPassword = false
    @Published var searchText = ""

    private var loadGeneration = UUID()
    @Published var searchAllEntries = true
    @Published var recentArchives: [URL] = (UserDefaults.standard.stringArray(forKey: "recentArchives") ?? []).map { URL(fileURLWithPath: $0) }
    private var archiveEntries: [ArchiveEntry] = []
    private(set) var archivePassword: String = ""
    private var backStack: [Location] = []
    private var forwardStack: [Location] = []
    var showHiddenFiles = false

    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        location = .folder(home)
        loadFolder(home)
    }

    var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        if location.isArchive && searchAllEntries {
            return archiveEntries.filter { !$0.isDirectory && $0.path.localizedCaseInsensitiveContains(searchText) }.map {
                Item(name: $0.path, path: $0.path, isDirectory: false,
                     isArchive: ArchiveService.isArchive(URL(fileURLWithPath: $0.path)),
                     size: $0.size, packedSize: $0.packedSize, modified: $0.modified,
                     attributes: $0.attributes, crc: $0.crc, encrypted: $0.encrypted)
            }
        }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var currentArchiveURL: URL? {
        if case let .archive(archive, _) = location { return archive }
        return nil
    }

    var currentFolderURL: URL? {
        if case let .folder(url) = location { return url }
        return nil
    }

    // MARK: - Navigation

    func go(to newLocation: Location, remember: Bool = true) {
        if remember {
            backStack.append(location)
            forwardStack.removeAll()
        }
        if currentArchiveURL != { if case let .archive(url, _) = newLocation { return url }; return nil }() {
            archivePassword = ""
        }
        searchText = ""
        location = newLocation
        reload()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        archivePassword = ""
        searchText = ""
        location = previous
        reload()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        archivePassword = ""
        searchText = ""
        location = next
        reload()
    }

    func goUp() {
        switch location {
        case let .folder(url):
            let parent = url.deletingLastPathComponent()
            if parent.path != url.path { go(to: .folder(parent)) }
        case let .archive(archive, inner):
            if inner.isEmpty {
                go(to: .folder(archive.deletingLastPathComponent()))
            } else {
                let parent = (inner as NSString).deletingLastPathComponent
                go(to: .archive(archive: archive, inner: parent))
            }
        }
    }

    /// Navigates to a path typed or pasted into the address bar.
    func openPath(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = (trimmed as NSString).expandingTildeInPath
        open(URL(fileURLWithPath: expanded))
    }

    func open(_ url: URL, asArchive: Bool = false) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            errorMessage = "Path not found: \(url.path)"
            return
        }
        errorMessage = nil
        if isDir.boolValue {
            go(to: .folder(url))
        } else if asArchive || ArchiveService.isArchive(url) {
            archivePassword = ""
            // For split archives always open through the first volume.
            let primary = ArchiveService.primaryVolume(url)
            recentArchives.removeAll { $0 == primary }
            recentArchives.insert(primary, at: 0)
            recentArchives = Array(recentArchives.prefix(8))
            UserDefaults.standard.set(recentArchives.map(\.path), forKey: "recentArchives")
            go(to: .archive(archive: primary, inner: ""))
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func activate(_ item: Item) {
        switch location {
        case .folder:
            open(URL(fileURLWithPath: item.path))
        case let .archive(archive, _):
            if item.isDirectory {
                go(to: .archive(archive: archive, inner: item.path))
            }
        }
    }

    func reload() {
        needsPassword = false
        switch location {
        case let .folder(url):
            loadFolder(url)
        case let .archive(archive, inner):
            loadArchive(archive, inner: inner, password: archivePassword)
        }
    }

    func unlock(with password: String) {
        archivePassword = password
        needsPassword = false
        reload()
    }

    // MARK: - Loading

    private func loadFolder(_ url: URL) {
        let generation = UUID()
        loadGeneration = generation
        items = []
        archiveEntries = []
        isLoading = true
        errorMessage = nil
        summary = nil
        let includeHidden = showHiddenFiles

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var options: FileManager.DirectoryEnumerationOptions = []
            if !includeHidden { options.insert(.skipsHiddenFiles) }
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
            } catch {
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            let mapped: [Item] = contents.map { child in
                let values = try? child.resourceValues(forKeys: Set(keys))
                let isDir = values?.isDirectory ?? false
                return Item(
                    name: child.lastPathComponent,
                    path: child.path,
                    isDirectory: isDir,
                    isArchive: !isDir && ArchiveService.isArchive(child),
                    size: Int64(values?.fileSize ?? 0),
                    packedSize: 0,
                    modified: values?.contentModificationDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            DispatchQueue.main.async {
                guard self.loadGeneration == generation else { return }
                self.items = mapped
                self.archiveEntries = []
                self.isLoading = false
            }
        }
    }

    private func loadArchive(_ archive: URL, inner: String, password: String) {
        let generation = UUID()
        loadGeneration = generation
        items = []
        archiveEntries = []
        isLoading = true
        errorMessage = nil

        summary = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let listing = try ArchiveService.list(archive: archive, password: password)
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.archiveEntries = listing.entries
                    self.summary = listing.summary
                    self.items = Self.items(from: listing.entries, inner: inner)
                    self.isLoading = false
                }
            } catch SevenZError.needsPassword {
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.needsPassword = true
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.items = []
                }
            }
        }
    }

    /// Turns a flat list of archive entries into the visible rows for one virtual folder.
    static func items(from entries: [ArchiveEntry], inner: String) -> [Item] {
        let prefix = inner.isEmpty ? "" : inner + "/"
        var folders: [String: Item] = [:]
        var files: [Item] = []

        for entry in entries {
            guard entry.path.hasPrefix(prefix) else { continue }
            let remainder = String(entry.path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            let parts = remainder.split(separator: "/").map(String.init)

            guard !parts.isEmpty else { continue }
            if parts.count == 1 {
                let item = Item(
                    name: parts[0],
                    path: prefix + parts[0],
                    isDirectory: entry.isDirectory,
                    isArchive: !entry.isDirectory && ArchiveService.isArchive(URL(fileURLWithPath: parts[0])),
                    size: entry.size,
                    packedSize: entry.packedSize,
                    modified: entry.modified,
                    attributes: entry.attributes,
                    crc: entry.crc,
                    encrypted: entry.encrypted
                )
                if entry.isDirectory {
                    var directory = item
                    directory.size += folders[parts[0]]?.size ?? 0
                    directory.packedSize += folders[parts[0]]?.packedSize ?? 0
                    folders[parts[0]] = directory
                } else {
                    files.append(item)
                }
            } else {
                let name = parts[0]
                var folder = folders[name] ?? Item(
                    name: name,
                    path: prefix + name,
                    isDirectory: true,
                    isArchive: false,
                    size: 0,
                    packedSize: 0,
                    modified: nil
                )
                folder.size += entry.size
                folder.packedSize += entry.packedSize
                folders[name] = folder
            }
        }

        let sortedFolders = folders.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let sortedFiles = files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return sortedFolders + sortedFiles
    }

    /// Every archive path covered by the current selection (folders expand to their children).
    func archivePaths(for selection: Set<String>) -> [String] {
        guard location.isArchive else { return Array(selection) }
        var result: [String] = []
        for path in selection {
            if let item = items.first(where: { $0.path == path }), item.isDirectory {
                result.append(path)
                result.append(contentsOf: archiveEntries
                    .map(\.path)
                    .filter { $0.hasPrefix(path + "/") })
            } else {
                result.append(path)
            }
        }
        return Array(Set(result)).sorted()
    }
}
