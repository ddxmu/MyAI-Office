import Cocoa

private struct MyAIOfficeSemanticVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        parts = numbers
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

private struct MyAIOfficeUpdateAsset: Decodable {
    let url: URL
    let sha256: String
    let baseVersion: String?
    let format: String?
    let size: Int64?

    var sizeDescription: String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "大小由服务器提供"
    }
    var isValid: Bool {
        let localQA = ProcessInfo.processInfo.environment["MYAI_OFFICE_QA"] == "1"
            && url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host ?? "")
        return (url.scheme == "https" || localQA) && sha256.count == 64
            && sha256.allSatisfy(\.isHexDigit) && (size ?? 1) > 0
    }
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
    case latest
    case available(version: String, notes: String)
    case downloading(version: String, progress: Double?, detail: String)
    case installing(version: String)
    case updated(version: String)
    case failed(message: String)
}

final class MyAIOfficeUpdateManager: NSObject, URLSessionDownloadDelegate {
    static let shared = MyAIOfficeUpdateManager()
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    var automaticChecks: Bool {
        get { UserDefaults.standard.bool(forKey: "MyAIAutomaticUpdateChecks") }
        set { UserDefaults.standard.set(newValue, forKey: "MyAIAutomaticUpdateChecks") }
    }

    private var timer: Timer?
    private var notifiedVersion: String?
    private weak var presentingWindow: NSWindow?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?
    private var downloadedFileURL: URL?
    private var downloadProcessingError: Error?
    private var downloadAlert: NSAlert?
    private weak var progressIndicator: NSProgressIndicator?
    private weak var progressLabel: NSTextField?
    private var pendingAsset: MyAIOfficeUpdateAsset?
    private var fullAsset: MyAIOfficeUpdateAsset?
    private var pendingVersion: String?
    private var pendingNotes = ""
    private var cancelled = false
    private var stateObserver: ((MyAIOfficeUpdateState) -> Void)?
    private(set) var state: MyAIOfficeUpdateState = .idle

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: ["MyAIAutomaticUpdateChecks": true])
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    func observe(_ observer: @escaping (MyAIOfficeUpdateState) -> Void) {
        stateObserver = observer
        observer(state)
    }

    func startAutomaticChecks(presenting window: NSWindow?) {
        presentingWindow = window
        if automaticChecks { checkForUpdates(presenting: window) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 60 * 60, repeats: true) { [weak self] _ in
            guard let self, self.automaticChecks else { return }
            self.checkForUpdates(presenting: self.presentingWindow)
        }
    }

    func startPendingUpdate(presenting window: NSWindow?) {
        presentingWindow = window
        guard !isBusy else { return }
        guard let asset = pendingAsset, let version = pendingVersion else {
            checkForUpdates(presenting: window, manual: true)
            return
        }
        guard confirmEditorsClosed() else { return }
        download(asset, targetVersion: version)
    }

    func checkForUpdates(presenting window: NSWindow?, manual: Bool = false) {
        guard !isBusy else { return }
        presentingWindow = window
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MyAIUpdateManifestURL") as? String,
              let url = URL(string: value) else {
            setState(.failed(message: "未配置更新地址。"))
            return
        }
        setState(.checking)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MyAI Office/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            do {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    throw MyAIUpdatePackage.Invalid("更新服务器暂时不可用，请稍后重试。")
                }
                let manifest = try JSONDecoder().decode(MyAIOfficeUpdateManifest.self, from: data)
                DispatchQueue.main.async { self?.receive(manifest, manual: manual) }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let version = self.pendingVersion {
                        self.setState(.available(version: version, notes: self.pendingNotes))
                    } else {
                        self.setState(.failed(message: "检查更新失败：\(error.localizedDescription)"))
                    }
                    if manual { self.showFailure("检查更新失败", error.localizedDescription) }
                }
            }
        }.resume()
    }

    private func receive(_ manifest: MyAIOfficeUpdateManifest, manual: Bool) {
        guard manifest.app == "MyAI Office", manifest.full.isValid,
              let current = MyAIOfficeSemanticVersion(Self.currentVersion),
              let latest = MyAIOfficeSemanticVersion(manifest.latestVersion) else {
            setState(.failed(message: "升级清单无效，请稍后重试。"))
            if manual { showFailure("检查更新失败", "升级清单无效。") }
            return
        }
        guard current < latest else {
            pendingAsset = nil
            pendingVersion = nil
            setState(.latest)
            return
        }
        let compatible = manifest.deltas.filter {
            $0.baseVersion == Self.currentVersion && $0.isValid
                && ($0.format == nil || $0.format == "file-delta-v1" || $0.format == "bsdiff-v2")
        }
        pendingAsset = compatible.first { $0.format == "bsdiff-v2" } ?? compatible.first ?? manifest.full
        fullAsset = manifest.full
        pendingVersion = manifest.latestVersion
        pendingNotes = manifest.releaseNotes.isEmpty ? "包含功能改进和问题修复。" : manifest.releaseNotes
        setState(.available(version: manifest.latestVersion, notes: pendingNotes))
        if manual || (notifiedVersion != manifest.latestVersion && NSApp.isActive && presentingWindow?.attachedSheet == nil) {
            notifiedVersion = manifest.latestVersion
            let alert = NSAlert()
            alert.messageText = "发现新版本 MyAI Office \(manifest.latestVersion)"
            let kind = pendingAsset?.baseVersion == nil ? "完整更新包" : "增量更新包"
            alert.informativeText = "\(pendingNotes)\n\n\(kind)：\(pendingAsset!.sizeDescription)。请先保存并关闭办公模块，更新后将自动重启。"
            alert.addButton(withTitle: "立即更新")
            alert.addButton(withTitle: "稍后")
            present(alert) { [weak self] result in
                if result == .alertFirstButtonReturn { self?.startPendingUpdate(presenting: self?.presentingWindow) }
            }
        }
    }

    private func confirmEditorsClosed() -> Bool {
        let prefix = Bundle.main.bundleURL.resolvingSymlinksInPath().appendingPathComponent("Contents/Helpers").path + "/"
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.resolvingSymlinksInPath().path.hasPrefix(prefix) == true && !$0.isTerminated
        }
        guard running.isEmpty else {
            let names = running.compactMap(\.localizedName).joined(separator: "、")
            showFailure("请先保存文档", "请保存并退出 \(names)，再点击“立即更新”。更新不会强制关闭你的文档。")
            return false
        }
        guard FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path) else {
            showFailure("无法安装到当前位置", "请先将 MyAI Office 拖入“应用程序”文件夹，退出安装盘中的副本，再检查更新。")
            return false
        }
        return true
    }

    private func download(_ asset: MyAIOfficeUpdateAsset, targetVersion: String) {
        guard downloadTask == nil else { return }
        cancelled = false
        downloadedFileURL = nil
        downloadProcessingError = nil
        setState(.downloading(version: targetVersion, progress: 0, detail: "准备下载…"))
        let alert = NSAlert()
        alert.messageText = "正在下载 MyAI Office \(targetVersion)"
        alert.informativeText = "下载 → 校验 → 安装 → 自动重启。完成前请不要关机或退出当前账户。"
        let accessory = NSStackView(frame: NSRect(x: 0, y: 0, width: 350, height: 52))
        accessory.orientation = .vertical
        accessory.alignment = .width
        accessory.spacing = 10
        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.doubleValue = 0
        indicator.setAccessibilityLabel("更新包下载进度")
        accessory.addArrangedSubview(indicator)
        let label = NSTextField(labelWithString: "0% · 准备下载 \(asset.sizeDescription)")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .center
        label.setAccessibilityIdentifier("update-download-detail")
        accessory.addArrangedSubview(label)
        alert.accessoryView = accessory
        let cancel = alert.addButton(withTitle: "取消下载")
        cancel.target = self
        cancel.action = #selector(cancelDownload)
        downloadAlert = alert
        progressIndicator = indicator
        progressLabel = label
        present(alert)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        downloadSession = session
        downloadTask = session.downloadTask(with: asset.url)
        downloadTask?.resume()
    }

    @objc private func cancelDownload() {
        cancelled = true
        downloadTask?.cancel()
        dismissDownloadAlert()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (pendingAsset?.size ?? 0)
        let progress = expected > 0 ? min(1, Double(totalBytesWritten) / Double(expected)) : nil
        let received = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let detail = progress.map {
            "\(Int($0 * 100))% · \(received) / \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))"
        } ?? "已下载 \(received)"
        DispatchQueue.main.async { [weak self] in
            guard let self, self.downloadTask === downloadTask, !self.cancelled else { return }
            self.progressIndicator?.isIndeterminate = progress == nil
            if progress == nil { self.progressIndicator?.startAnimation(nil) }
            self.progressIndicator?.doubleValue = progress ?? 0
            self.progressLabel?.stringValue = detail
            self.setState(.downloading(version: self.pendingVersion ?? "", progress: progress, detail: detail))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyAI-Office-update-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: url)
            downloadedFileURL = url
        } catch { downloadProcessingError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let response = task.response as? HTTPURLResponse
        DispatchQueue.main.async { [weak self] in
            guard let self, self.downloadTask === task else { return }
            let local = self.downloadedFileURL
            let processingError = self.downloadProcessingError
            self.downloadTask = nil
            self.downloadSession = nil
            self.downloadedFileURL = nil
            self.downloadProcessingError = nil
            session.finishTasksAndInvalidate()
            if self.cancelled {
                if let local { try? FileManager.default.removeItem(at: local) }
                if let version = self.pendingVersion {
                    self.setState(.available(version: version, notes: self.pendingNotes))
                }
                return
            }
            guard error == nil, processingError == nil, let local,
                  let response, (200..<300).contains(response.statusCode) else {
                if let local { try? FileManager.default.removeItem(at: local) }
                self.failDownload((error ?? processingError)?.localizedDescription ?? "更新服务器返回错误，请重试。")
                return
            }
            self.prepare(local)
        }
    }

    private func prepare(_ package: URL) {
        guard let asset = pendingAsset, let target = pendingVersion else { return }
        setState(.installing(version: target))
        downloadAlert?.messageText = "正在安装 MyAI Office \(target)"
        downloadAlert?.buttons.first?.isEnabled = false
        progressIndicator?.isIndeterminate = true
        progressIndicator?.startAnimation(nil)
        progressLabel?.stringValue = "下载完成，正在校验并准备安装…"
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let staged = app.deletingLastPathComponent().appendingPathComponent(".MyAI Office.staged-\(UUID().uuidString).app")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard try MyAIUpdatePackage.sha256(package).caseInsensitiveCompare(asset.sha256) == .orderedSame else {
                    throw MyAIUpdatePackage.Invalid("下载文件校验失败，请重新下载。")
                }
                try MyAIUpdatePackage.stage(package: package, base: app, destination: staged, targetVersion: target)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.dismissDownloadAlert()
                    guard self.confirmEditorsClosed() else {
                        try? FileManager.default.removeItem(at: staged)
                        try? FileManager.default.removeItem(at: package)
                        self.setState(.available(version: target, notes: self.pendingNotes))
                        return
                    }
                    self.launchUpdater(staged: staged, package: package, target: target)
                }
            } catch {
                try? FileManager.default.removeItem(at: package)
                DispatchQueue.main.async { self?.preparationFailed(error, asset: asset) }
            }
        }
    }

    private func preparationFailed(_ error: Error, asset: MyAIOfficeUpdateAsset) {
        dismissDownloadAlert()
        if asset.baseVersion != nil, let fullAsset, let target = pendingVersion {
            pendingAsset = fullAsset
            setState(.available(version: target, notes: pendingNotes))
            let alert = NSAlert()
            alert.messageText = "增量更新无法应用"
            alert.informativeText = "\(error.localizedDescription)\n当前应用未被修改。是否改用完整更新包（\(fullAsset.sizeDescription)）？"
            alert.addButton(withTitle: "下载完整包")
            alert.addButton(withTitle: "稍后")
            present(alert) { [weak self] result in
                if result == .alertFirstButtonReturn { self?.startPendingUpdate(presenting: self?.presentingWindow) }
            }
        } else {
            failDownload(error.localizedDescription)
        }
    }

    private func launchUpdater(staged: URL, package: URL, target: String) {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("myai-installer-\(UUID().uuidString)")
        let receipt = MyAIUpdateReceipt.directory.appendingPathComponent("\(UUID().uuidString).json")
        do {
            let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
            let source = app.appendingPathComponent("Contents/Helpers/myai-office-updater")
            guard fm.isExecutableFile(atPath: source.path) else {
                throw MyAIUpdatePackage.Invalid("当前应用缺少更新助手，请重新安装完整包。")
            }
            try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
            let helper = temporary.appendingPathComponent("myai-office-updater")
            try fm.copyItem(at: source, to: helper)
            try MyAIUpdateReceipt(targetVersion: target, appPath: app.path, state: "pending").write(receipt)
            let task = Process()
            task.executableURL = helper
            task.arguments = ["--pid", String(ProcessInfo.processInfo.processIdentifier),
                "--app", app.path, "--staged", staged.path, "--package", package.path,
                "--base-version", Self.currentVersion, "--target-version", target, "--receipt", receipt.path]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            try? fm.removeItem(at: staged)
            try? fm.removeItem(at: package)
            try? fm.removeItem(at: receipt)
            try? fm.removeItem(at: temporary)
            failDownload(error.localizedDescription)
        }
    }

    func finishPendingUpdate(presenting window: NSWindow?) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--myai-update-result"), args.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: args[index + 1]).standardizedFileURL
        do {
            var result = try MyAIUpdateReceipt.read(url)
            guard result.state == "pending", result.targetVersion == Self.currentVersion,
                  result.appPath == Bundle.main.bundleURL.resolvingSymlinksInPath().path else { return }
            result.state = "success"
            try result.write(url)
            presentingWindow = window
            setState(.updated(version: Self.currentVersion))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "更新完成"
                alert.informativeText = "MyAI Office 已更新到 \(Self.currentVersion)，并已自动重新启动。"
                alert.addButton(withTitle: "开始使用")
                self.present(alert)
            }
        } catch { setState(.failed(message: "无法确认更新结果：\(error.localizedDescription)")) }
    }

    private func failDownload(_ message: String) {
        dismissDownloadAlert()
        setState(.failed(message: message))
        showFailure("更新失败", message + "\n原应用未被替换，你可以重试。")
    }

    private func setState(_ newState: MyAIOfficeUpdateState) {
        state = newState
        stateObserver?(newState)
    }

    private func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        if let window = presentingWindow ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else if let completion { completion(alert.runModal()) }
        else { alert.runModal() }
    }

    private func dismissDownloadAlert() {
        guard let alert = downloadAlert else { return }
        downloadAlert = nil
        progressIndicator = nil
        progressLabel = nil
        if let parent = alert.window.sheetParent { parent.endSheet(alert.window, returnCode: .abort) }
        else { NSApp.abortModal(); alert.window.orderOut(nil) }
    }

    private func showFailure(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        // Ending an earlier progress sheet is asynchronous in AppKit.
        DispatchQueue.main.async { self.present(alert) }
    }
}
