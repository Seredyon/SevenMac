import SwiftUI

@main
struct SevenMacApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var browser = BrowserModel()
    @StateObject private var job = JobRunner()

    var body: some Scene {
        WindowGroup("SevenMac") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(browser)
                .environmentObject(job)
                .frame(minWidth: 940, minHeight: 580)
                .onAppear { SevenZRunner.shared.binaryPath = settings.customBinaryPath }
        }
        .commands { AppCommands() }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

enum AppAction: String {
    case open, add, extractHere, extractTo, test, refresh, up, benchmark, hash, info, delete, rename

    var notification: Notification.Name { Notification.Name("SevenMac." + rawValue) }

    func post() { NotificationCenter.default.post(name: notification, object: nil) }
}

extension View {
    func onAppAction(_ action: AppAction, perform: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: action.notification)) { _ in perform() }
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open\u{2026}") { AppAction.open.post() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu("Archive") {
            Button("Add to Archive\u{2026}") { AppAction.add.post() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Extract Here") { AppAction.extractHere.post() }
                .keyboardShortcut("e", modifiers: .command)
            Button("Extract To\u{2026}") { AppAction.extractTo.post() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Test Integrity") { AppAction.test.post() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Checksums\u{2026}") { AppAction.hash.post() }
            Button("Archive Info") { AppAction.info.post() }
            Divider()
            Button("Benchmark\u{2026}") { AppAction.benchmark.post() }
        }
        CommandGroup(after: .sidebar) {
            Button("Enclosing Folder") { AppAction.up.post() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Refresh") { AppAction.refresh.post() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}
