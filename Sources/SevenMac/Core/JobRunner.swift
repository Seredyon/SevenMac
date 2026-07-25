import Foundation
import SwiftUI

/// Runs a single 7zz job at a time and publishes progress for the progress sheet.
final class JobRunner: ObservableObject {
    @Published var isRunning = false
    @Published var title = ""
    @Published var detail = ""
    @Published var fraction: Double = 0
    @Published var indeterminate = true
    @Published var lastLog = ""
    @Published var alert: AlertPayload?

    private var process: Process?
    private var cancelRequested = false
    private let queue = DispatchQueue(label: "io.sevenmac.job", qos: .userInitiated)

    struct AlertPayload: Identifiable {
        let id = UUID()
        var title: String
        var message: String
        var isError: Bool
        var hasDetails: Bool = false
    }

    func run(title: String,
             arguments: [String],
             password: String? = nil,
             workingDirectory: URL? = nil,
             successMessage: String? = nil,
             completion: ((Result<SevenZResult, Error>) -> Void)? = nil) {

        guard !isRunning else { return }
        self.title = title
        self.detail = "Starting\u{2026}"
        self.fraction = 0
        self.indeterminate = true
        self.isRunning = true
        self.cancelRequested = false

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try SevenZRunner.shared.run(
                    arguments,
                    password: password,
                    workingDirectory: workingDirectory,
                    wantsProgress: true,
                    onProcess: { proc in
                        DispatchQueue.main.async { self.process = proc }
                    },
                    onProgress: { value, text in
                        DispatchQueue.main.async {
                            self.indeterminate = false
                            self.fraction = value
                            if !text.isEmpty { self.detail = text }
                        }
                    }
                )
                DispatchQueue.main.async {
                    self.finish()
                    self.lastLog = result.output
                    if let successMessage {
                        self.alert = AlertPayload(title: "Done", message: successMessage, isError: false)
                    }
                    completion?(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    self.finish()
                    // A cancel the user asked for is not an error - stay quiet.
                    if self.cancelRequested || (error as? SevenZError).map({ if case .cancelled = $0 { return true } else { return false } }) == true {
                        completion?(.failure(SevenZError.cancelled))
                        return
                    }
                    if case let SevenZError.failed(_, output) = error {
                        self.lastLog = SevenZRunner.cleanOutput(output)
                    }
                    self.alert = AlertPayload(
                        title: "7-Zip reported a problem",
                        message: error.localizedDescription,
                        isError: true,
                        hasDetails: !self.lastLog.isEmpty
                    )
                    completion?(.failure(error))
                }
            }
        }
    }

    func cancel() {
        cancelRequested = true
        process?.terminate()
    }

    private func finish() {
        isRunning = false
        process = nil
        detail = ""
    }
}
