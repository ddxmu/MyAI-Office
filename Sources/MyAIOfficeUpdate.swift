import Cocoa
import CryptoKit

private struct MyAIOfficeSemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: MyAIOfficeSemanticVersion, rhs: MyAIOfficeSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

private struct MyAIOfficeUpdateAsset: Decodable {
    let url: URL
    let sha256: String
    let baseVersion: String?
}

private struct MyAIOfficeUpdateManifest: Decodable {
    let app: String
    let latestVersion: String
    let releaseNotes: String
    let full: MyAIOfficeUpdateAsset
    let deltas: [MyAIOfficeUpdateAsset]
}

enum MyAIOfficeUpdateState {
    case idle
    case checking
    case available(version: String, notes: String)
    case downloading(version: String)
    case installing(version: String)
    case failed(message: String)
}

private enum MyAIOfficeUpdateError: LocalizedError {
    case invalidResponse
    case checksumMismatch
    case updaterMissing

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "升级服务器返回了无效内容。"
        case .checksumMismatch: return "升级包校验失败，文件可能已损坏。"
        case .updaterMissing: return "当前安装包缺少升级助手，请重新安装最新完整包。"
        }
    }
}

final class MyAIOfficeUpdateManager: NSObject {
    static let shared = MyAIOfficeUpdateManager()

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var hasChecked = false
    private weak var presentingWindow: NSWindow?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadAlert: NSAlert?
    private var pendingAsset: MyAIOfficeUpdateAsset?
    private var pendingVersion: String?
    private var stateObserver: ((MyAIOfficeUpdateState) -> Void)?
    private(set) var state: MyAIOfficeUpdateState = .idle

    private var manifestURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MyAIUpdateManifestURL") as? String else { return nil }
        return URL(string: value)
    }

    func observe(_ observer: @escaping (MyAIOfficeUpdateState) -> Void) {
        stateObserver = observer
        let currentState = state
        if Thread.isMainThread {
            observer(currentState)
        } else {
            DispatchQueue.main.async { observer(currentState) }
        }
    }

    func startPendingUpdate() {
        guard let asset = pendingAsset, let version = pendingVersion else { return }
        switch state {
        case .available, .failed:
            download(asset, targetVersion: version)
        default:
            break
        }
    }

    func checkForUpdates(presenting window: NSWindow?) {
        guard !hasChecked else { return }
        hasChecked = true
        presentingWindow = window
        guard let manifestURL else { return }
        setState(.checking)

        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("MyAI Office/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, error == nil,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data else { return }
            do {
                let manifest = try JSONDecoder().decode(MyAIOfficeUpdateManifest.self, from: data)
                DispatchQueue.main.async {
                    self.offerUpdateIfNeeded(manifest)
                }
            } catch {
                // Update checks are intentionally silent when the network is unavailable
                // or the manifest is not yet published.
            }
        }.resume()
    }

    private func offerUpdateIfNeeded(_ manifest: MyAIOfficeUpdateManifest) {
        guard manifest.app == "MyAI Office",
              let current = MyAIOfficeSemanticVersion(Self.currentVersion),
              let latest = MyAIOfficeSemanticVersion(manifest.latestVersion),
              current < latest else { return }

        let delta = manifest.deltas.first { $0.baseVersion == Self.currentVersion }
        let asset = delta ?? manifest.full
        let notes = manifest.releaseNotes.isEmpty ? "包含功能改进和问题修复。" : manifest.releaseNotes
        pendingAsset = asset
        pendingVersion = manifest.latestVersion
        setState(.available(version: manifest.latestVersion, notes: notes))
    }

    private func download(_ asset: MyAIOfficeUpdateAsset, targetVersion: String) {
        guard downloadTask == nil else { return }
        setState(.downloading(version: targetVersion))

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "正在下载 MyAI Office \(targetVersion)"
        alert.informativeText = "下载完成后会自动校验、替换并重启应用，请不要退出当前账户。"
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 20))
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.startAnimation(nil)
        alert.accessoryView = indicator
        alert.addButton(withTitle: "正在下载…").isEnabled = false
        downloadAlert = alert
        present(alert)

        downloadTask = URLSession.shared.downloadTask(with: asset.url) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            do {
                guard error == nil, let temporaryURL,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw MyAIOfficeUpdateError.invalidResponse
                }

                let localURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MyAI-Office-update-\(UUID().uuidString).zip")
                try? FileManager.default.removeItem(at: localURL)
                try FileManager.default.moveItem(at: temporaryURL, to: localURL)
                guard try Self.sha256(of: localURL).caseInsensitiveCompare(asset.sha256) == .orderedSame else {
                    throw MyAIOfficeUpdateError.checksumMismatch
                }

                DispatchQueue.main.async {
                    self.downloadTask = nil
                    self.setState(.installing(version: targetVersion))
                    self.dismissDownloadAlert {
                        self.launchUpdater(package: localURL, targetVersion: targetVersion)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.downloadTask = nil
                    self.dismissDownloadAlert {
                        self.setState(.failed(message: error.localizedDescription))
                        self.showFailure(error)
                    }
                }
            }
        }
        downloadTask?.resume()
    }

    private func launchUpdater(package: URL, targetVersion: String) {
        let updater = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("myai-office-updater")
        guard FileManager.default.isExecutableFile(atPath: updater.path) else {
            setState(.failed(message: MyAIOfficeUpdateError.updaterMissing.localizedDescription))
            showFailure(MyAIOfficeUpdateError.updaterMissing)
            return
        }

        let task = Process()
        task.executableURL = updater
        task.arguments = [
            "--apply",
            "--pid", String(ProcessInfo.processInfo.processIdentifier),
            "--app", Bundle.main.bundleURL.path,
            "--package", package.path,
            "--target-version", targetVersion
        ]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            setState(.failed(message: error.localizedDescription))
            showFailure(error)
        }
    }

    private func setState(_ newState: MyAIOfficeUpdateState) {
        let apply = { [weak self] in
            guard let self else { return }
            self.state = newState
            self.stateObserver?(newState)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = presentingWindow ?? NSApp.keyWindow {
            if let completion {
                alert.beginSheetModal(for: window, completionHandler: completion)
            } else {
                alert.beginSheetModal(for: window)
            }
        } else if let completion {
            completion(alert.runModal())
        } else {
            alert.runModal()
        }
    }

    private func dismissDownloadAlert(completion: @escaping () -> Void) {
        guard let alert = downloadAlert else {
            completion()
            return
        }
        downloadAlert = nil
        let alertWindow = alert.window
        if let parent = alertWindow.sheetParent {
            parent.endSheet(alertWindow, returnCode: .abort)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: completion)
        } else {
            completion()
        }
    }

    private func showFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "升级失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        present(alert)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
