import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var browser: BrowserModel
    @EnvironmentObject var job: JobRunner

    @State private var selection = Set<Item.ID>()
    @State private var sortOrder: [KeyPathComparator<Item>] = [KeyPathComparator(\Item.name)]
    @State private var sheet: ActiveSheet?
    @State private var dropTargeted = false

    enum ActiveSheet: Identifiable {
        case welcome
        case add([URL])
        case extractTo([String])
        case password
        case info
        case benchmark
        case textReport(String, String)

        var id: String {
            switch self {
            case .welcome: return "welcome"
            case .add: return "add"
            case .extractTo: return "extract"
            case .password: return "password"
            case .info: return "info"
            case .benchmark: return "benchmark"
            case let .textReport(title, _): return "report-" + title
            }
        }
    }

    /// Rows shown in the table: filtered by the search field, ordered by the
    /// active column sort (folders always stay grouped before files).
    private var rows: [Item] {
        let sorted = browser.filteredItems.sorted(using: sortOrder)
        let folders = sorted.filter(\.isDirectory)
        let files = sorted.filter { !$0.isDirectory }
        return folders + files
    }

    var body: some View {
        NavigationSplitView {
            SidebarView { url in
                selection.removeAll()
                browser.open(url)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            VStack(spacing: 0) {
                PathBar(location: browser.location,
                        summary: browser.summary,
                        onNavigate: { path in
                            selection.removeAll()
                            browser.openPath(path)
                        },
                        onUp: { browser.goUp() },
                        onBack: { browser.goBack() },
                        onForward: { browser.goForward() },
                        canGoBack: browser.canGoBack,
                        canGoForward: browser.canGoForward)
                Divider()
                fileTable
                Divider()
                StatusBar(itemCount: rows.count,
                          selectedCount: selection.count,
                          summary: browser.summary,
                          isLoading: browser.isLoading,
                          errorMessage: browser.errorMessage)
            }
            .toolbar { toolbarContent }
            .searchable(text: $browser.searchText, placement: .toolbar, prompt: "Filter")
        }
        .sheet(item: $sheet) { active in
            switch active {
            case .welcome:
                WelcomeSheet { settings.didShowWelcome = true }
                    .interactiveDismissDisabled()
            case let .add(inputs):
                AddArchiveSheet(inputs: inputs) { archiveURL, options in
                    startAdd(archive: archiveURL, inputs: inputs, options: options)
                }
                .environmentObject(settings)
            case let .extractTo(paths):
                ExtractSheet(archiveName: browser.currentArchiveURL?.lastPathComponent ?? "",
                             suggestedDestination: defaultExtractDestination(),
                             selectedPaths: paths,
                             requiresPassword: browser.summary?.isEncrypted ?? false) { options in
                    startExtract(options: options)
                }
            case .password:
                PasswordSheet(archiveName: browser.currentArchiveURL?.lastPathComponent ?? "") { password in
                    browser.unlock(with: password)
                }
            case .info:
                InfoSheet(location: browser.location, summary: browser.summary)
            case .benchmark:
                BenchmarkView()
            case let .textReport(title, body):
                TextReportSheet(title: title, text: body)
            }
        }
        .overlay {
            if job.isRunning {
                ProgressSheet()
                    .environmentObject(job)
                    .transition(.opacity)
            }
        }
        .alert(item: $job.alert) { payload in
            // Short message + optional "Details" button; the full log opens in a
            // scrollable window so the alert itself can never outgrow the screen.
            if payload.hasDetails {
                return Alert(
                    title: Text(payload.title),
                    message: Text(payload.message),
                    primaryButton: .default(Text("OK")),
                    secondaryButton: .default(Text("Show Details")) {
                        sheet = .textReport("7-Zip log", job.lastLog)
                    }
                )
            }
            return Alert(title: Text(payload.title),
                         message: Text(payload.message),
                         dismissButton: .default(Text("OK")))
        }
        .onAppear {
            if !settings.didShowWelcome { sheet = .welcome }
        }
        .onChange(of: browser.needsPassword) { needs in
            if needs { sheet = .password }
        }
        .onChange(of: settings.showHiddenFiles) { value in
            browser.showHiddenFiles = value
            browser.reload()
        }
        .onAppAction(.open) { openPanel() }
        .onAppAction(.add) { beginAdd() }
        .onAppAction(.extractHere) { extractHere() }
        .onAppAction(.extractTo) { if canExtract { sheet = .extractTo(selectedArchivePaths()) } }
        .onAppAction(.test) { testArchive() }
        .onAppAction(.refresh) { browser.reload() }
        .onAppAction(.up) { browser.goUp() }
        .onAppAction(.benchmark) { sheet = .benchmark }
        .onAppAction(.hash) { computeHash() }
        .onAppAction(.info) { sheet = .info }
    }

    // MARK: - Table

    private var fileTable: some View {
        // Selection is left entirely to the Table: single click selects,
        // Cmd/Shift extend, double-click (primaryAction) opens.
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \Item.name) { item in
                HStack(spacing: 8) {
                    Image(systemName: icon(for: item))
                        .foregroundStyle(item.isArchive ? Color.accentColor : Color.secondary)
                    Text(item.name).lineLimit(1)
                    if item.encrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Size", value: \Item.size) { item in
                Text(item.isDirectory && !browser.location.isArchive ? "\u{2014}" : Formatting.size(item.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Packed", value: \Item.packedSize) { item in
                Text(item.packedSize > 0 ? Formatting.size(item.packedSize) : "\u{2014}")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Ratio", value: \Item.ratio) { item in
                Text(Formatting.percent(item.ratio))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Modified", value: \Item.modifiedTimestamp) { item in
                Text(Formatting.date(item.modified))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 170)
            TableColumn("Kind", value: \Item.kind) { item in
                Text(item.kind).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: Item.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let item = browser.items.first(where: { $0.id == id }) {
                browser.activate(item)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Item.ID>) -> some View {
        // Extract only makes sense inside an archive or for selected archive files.
        if extractableSelection(ids) {
            Button { syncSelection(ids); extractHere() } label: { Label("Extract Here", systemImage: "arrow.down.doc") }
            Button { syncSelection(ids); sheet = .extractTo(selectedArchivePaths()) } label: { Label("Extract To\u{2026}", systemImage: "tray.and.arrow.down") }
            Divider()
        }
        Button { syncSelection(ids); beginAdd() } label: { Label("Add to Archive\u{2026}", systemImage: "plus.rectangle.on.folder") }
        if checksumableSelection(ids) {
            Button { syncSelection(ids); computeHash() } label: { Label("Checksums\u{2026}", systemImage: "number") }
        }
        Divider()
        Button { syncSelection(ids); revealInFinder() } label: { Label("Reveal in Finder", systemImage: "magnifyingglass") }
        Button(role: .destructive) { syncSelection(ids); deleteSelection() } label: { Label("Delete", systemImage: "trash") }
    }

    /// Right-clicking a row that is not part of the current selection should
    /// act on that row, exactly like Finder.
    private func syncSelection(_ ids: Set<Item.ID>) {
        if !ids.isEmpty { selection = ids }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { browser.goUp() } label: {
                Label("Up", systemImage: "arrow.up").labelStyle(.titleAndIcon)
            }
            .help("Go to the enclosing folder (\u{2318}\u{2191})")
        }
        ToolbarItemGroup {
            Button { beginAdd() } label: {
                Label("Add", systemImage: "plus.rectangle.on.folder").labelStyle(.titleAndIcon)
            }
            .help("Create an archive from the selection (\u{21E7}\u{2318}A)")

            Button { extractHere() } label: {
                Label("Extract", systemImage: "arrow.down.doc").labelStyle(.titleAndIcon)
            }
            .disabled(!canExtract)
            .help("Extract next to the archive (\u{2318}E)")

            Button { sheet = .extractTo(selectedArchivePaths()) } label: {
                Label("Extract To", systemImage: "tray.and.arrow.down").labelStyle(.titleAndIcon)
            }
            .disabled(!canExtract)
            .help("Choose a destination and options (\u{21E7}\u{2318}E)")

            Button { testArchive() } label: {
                Label("Test", systemImage: "checkmark.seal").labelStyle(.titleAndIcon)
            }
            .disabled(!canExtract)
            .help("Verify archive integrity (\u{21E7}\u{2318}T)")

            Button { computeHash() } label: {
                Label("Checksum", systemImage: "number").labelStyle(.titleAndIcon)
            }
            .disabled(!canChecksum)
            .help("Calculate SHA-256 for the selected files or the current archive")

            Button { sheet = .info } label: {
                Label("Info", systemImage: "info.circle").labelStyle(.titleAndIcon)
            }
            .help("Show details for the current folder or archive")

            Button { browser.reload() } label: {
                Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
            }
            .help("Reload the current folder or archive (\u{2318}R)")
        }
    }

    // MARK: - Derived state

    private var canExtract: Bool {
        if browser.location.isArchive { return true }
        return selectedURLs().contains { ArchiveService.isArchive($0) && isFile($0) }
    }

    /// Checksums are offered for the archive being browsed or for selected
    /// plain files - not for folders.
    private var canChecksum: Bool {
        if browser.location.isArchive { return true }
        let urls = selectedURLs()
        return !urls.isEmpty && urls.allSatisfy { isFile($0) }
    }

    private func isFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private func extractableSelection(_ ids: Set<Item.ID>) -> Bool {
        if browser.location.isArchive { return true }
        return ids.contains { id in
            let url = URL(fileURLWithPath: id)
            return ArchiveService.isArchive(url) && isFile(url)
        }
    }

    private func checksumableSelection(_ ids: Set<Item.ID>) -> Bool {
        if browser.location.isArchive { return true }
        return !ids.isEmpty && ids.allSatisfy { isFile(URL(fileURLWithPath: $0)) }
    }

    private func icon(for item: Item) -> String {
        if item.isDirectory { return "folder.fill" }
        if item.isArchive { return "doc.zipper" }
        return "doc"
    }

    private func selectedURLs() -> [URL] {
        guard case .folder = browser.location else { return [] }
        return selection.map { URL(fileURLWithPath: $0) }
    }

    private func selectedArchivePaths() -> [String] {
        guard browser.location.isArchive else { return [] }
        return browser.archivePaths(for: selection)
    }

    private func defaultExtractDestination() -> URL {
        if let archive = browser.currentArchiveURL {
            return archive.deletingLastPathComponent()
                .appendingPathComponent(archive.deletingPathExtension().lastPathComponent)
        }
        if let folder = browser.currentFolderURL { return folder }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    // MARK: - Actions

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selection.removeAll()
            browser.open(url)
        }
    }

    private func beginAdd() {
        var inputs = selectedURLs()
        if inputs.isEmpty, let folder = browser.currentFolderURL {
            inputs = [folder]
        }
        guard !inputs.isEmpty else { return }
        sheet = .add(inputs)
    }

    private func startAdd(archive: URL, inputs: [URL], options: AddOptions) {
        // Run 7zz from the inputs' parent folder and pass relative names, so
        // stored paths start at the item itself (like 7-Zip on Windows) instead
        // of embedding /Users/<name>/... into the archive.
        let parent = inputs[0].deletingLastPathComponent()
        let sameParent = inputs.allSatisfy { $0.deletingLastPathComponent().path == parent.path }
        let inputPaths = sameParent ? inputs.map(\.lastPathComponent) : inputs.map(\.path)

        let args = ArchiveService.addArguments(archive: archive, inputPaths: inputPaths, options: options)
        job.run(title: "Compressing to \(archive.lastPathComponent)",
                arguments: args,
                password: options.password,
                workingDirectory: sameParent ? parent : nil,
                successMessage: options.volumeSize.isEmpty
                    ? "Created \(archive.lastPathComponent)"
                    : "Created \(archive.lastPathComponent).001, \u{2026} (volumes of \(options.volumeSize))") { result in
            if case .success = result {
                browser.reload()
                if settings.revealAfterExtract {
                    NSWorkspace.shared.activateFileViewerSelecting([archive.deletingLastPathComponent()])
                }
            }
        }
    }

    private func extractHere() {
        guard canExtract else { return }
        if browser.location.isArchive, let archive = browser.currentArchiveURL {
            let options = ExtractOptions(
                destination: defaultExtractDestination(),
                keepFullPaths: true,
                overwrite: .renameNew,
                password: browser.archivePassword,
                selectedPaths: selectedArchivePaths()
            )
            runExtract(archive: archive, options: options)
        } else {
            let archives = selectedURLs().filter { ArchiveService.isArchive($0) }
            guard let archive = archives.first.map({ ArchiveService.primaryVolume($0) }) else { return }
            var base = archive.deletingPathExtension()
            if ArchiveService.isVolumeSuffix(archive.pathExtension.lowercased()) {
                base = base.deletingPathExtension()
            }
            let destination = archive.deletingLastPathComponent()
                .appendingPathComponent(base.lastPathComponent)
            runExtract(archive: archive,
                       options: ExtractOptions(destination: destination))
        }
    }

    private func startExtract(options: ExtractOptions) {
        let archive: URL?
        if browser.location.isArchive {
            archive = browser.currentArchiveURL
        } else {
            archive = selectedURLs().first { ArchiveService.isArchive($0) }
        }
        guard let archive = archive.map({ ArchiveService.primaryVolume($0) }) else { return }
        runExtract(archive: archive, options: options)
    }

    private func runExtract(archive: URL, options: ExtractOptions) {
        let args = ArchiveService.extractArguments(archive: archive, options: options)
        let password = options.password.isEmpty ? browser.archivePassword : options.password
        job.run(title: "Extracting \(archive.lastPathComponent)",
                arguments: args,
                password: password,
                successMessage: "Extracted to \(options.destination.path)") { result in
            if case .success = result {
                if settings.revealAfterExtract {
                    NSWorkspace.shared.activateFileViewerSelecting([options.destination])
                }
                browser.reload()
            }
        }
    }

    private func testArchive() {
        let archive: URL?
        if browser.location.isArchive {
            archive = browser.currentArchiveURL
        } else {
            archive = selectedURLs().first { ArchiveService.isArchive($0) }
        }
        guard let archive = archive.map({ ArchiveService.primaryVolume($0) }) else { return }
        job.run(title: "Testing \(archive.lastPathComponent)",
                arguments: ArchiveService.testArguments(archive: archive),
                password: browser.archivePassword) { result in
            if case let .success(value) = result {
                sheet = .textReport("Test result", reportText(value.output))
            }
        }
    }

    /// Never show a fully blank report window - fall back to the raw job log.
    private func reportText(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return output }
        let log = job.lastLog.trimmingCharacters(in: .whitespacesAndNewlines)
        return log.isEmpty ? "The command finished successfully but produced no output." : log
    }

    private func computeHash() {
        guard canChecksum else { return }
        var targets = selectedURLs().filter { isFile($0) }
        if targets.isEmpty, let archive = browser.currentArchiveURL { targets = [archive] }
        guard !targets.isEmpty else { return }
        job.run(title: "Calculating checksums",
                arguments: ArchiveService.hashArguments(paths: targets, algorithm: .sha256)) { result in
            if case let .success(value) = result {
                sheet = .textReport("SHA-256", reportText(value.output))
            }
        }
    }

    private func deleteSelection() {
        if browser.location.isArchive, let archive = browser.currentArchiveURL {
            let paths = selectedArchivePaths()
            guard !paths.isEmpty else { return }
            job.run(title: "Removing from \(archive.lastPathComponent)",
                    arguments: ArchiveService.deleteArguments(archive: archive, paths: paths),
                    password: browser.archivePassword,
                    successMessage: "Removed \(paths.count) item(s)") { _ in
                selection.removeAll()
                browser.reload()
            }
        } else {
            for url in selectedURLs() {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            selection.removeAll()
            browser.reload()
        }
    }

    private func revealInFinder() {
        let urls = selectedURLs()
        if urls.isEmpty, let archive = browser.currentArchiveURL {
            NSWorkspace.shared.activateFileViewerSelecting([archive])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data,
                      let path = String(data: data, encoding: .utf8),
                      let url = URL(string: path) else { return }
                urls.append(url)
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            if urls.count == 1, urls[0].hasDirectoryPath || ArchiveService.isArchive(urls[0]) {
                browser.open(urls[0])
            } else {
                sheet = .add(urls)
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    var onSelect: (URL) -> Void

    private struct Place: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let url: URL
    }

    private var places: [Place] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            Place(name: "Home", icon: "house", url: home),
            Place(name: "Desktop", icon: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop")),
            Place(name: "Documents", icon: "doc.text", url: home.appendingPathComponent("Documents")),
            Place(name: "Downloads", icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            Place(name: "Applications", icon: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications")),
            Place(name: "Root", icon: "externaldrive", url: URL(fileURLWithPath: "/"))
        ]
    }

    var body: some View {
        List {
            Section("Places") {
                ForEach(places) { place in
                    Button {
                        onSelect(place.url)
                    } label: {
                        Label(place.name, systemImage: place.icon)
                    }
                    .buttonStyle(.plain)
                    .help(place.url.path)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Path bar (editable address field)

struct PathBar: View {
    let location: Location
    let summary: ArchiveSummary?
    var onNavigate: (String) -> Void
    var onUp: () -> Void
    var onBack: () -> Void
    var onForward: () -> Void
    var canGoBack: Bool
    var canGoForward: Bool

    @State private var editedPath = ""
    @FocusState private var pathFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                    .help("Back")
                Button(action: onForward) { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                    .help("Forward")
                Button(action: onUp) { Image(systemName: "arrow.up") }
                    .help("Enclosing folder (\u{2318}\u{2191})")
            }
            .buttonStyle(.borderless)

            Image(systemName: location.isArchive ? "doc.zipper" : "folder")
                .foregroundStyle(location.isArchive ? Color.accentColor : Color.secondary)

            // Editable address bar: type or paste any path and press Return.
            TextField("Path", text: $editedPath)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($pathFocused)
                .onSubmit {
                    onNavigate(editedPath)
                    pathFocused = false
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    // NSColor.quaternarySystemFill requires macOS 14; this look-alike works on macOS 13.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                )
                .help("Type or paste a path and press Return")

            if let summary, location.isArchive {
                Text(summary.type.uppercased())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { editedPath = location.displayPath }
        .onChange(of: location) { newValue in
            editedPath = newValue.displayPath
            pathFocused = false
        }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    let itemCount: Int
    let selectedCount: Int
    let summary: ArchiveSummary?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Text("\(itemCount) items")
            if selectedCount > 0 {
                Text("\u{2022} \(selectedCount) selected")
            }
            if let summary, summary.fileCount > 0 {
                Text("\u{2022} \(Formatting.size(summary.totalSize)) \u{2192} \(Formatting.size(summary.packedSize)) (\(Formatting.percent(summary.ratio)))")
            }
            Spacer()
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(errorMessage)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
