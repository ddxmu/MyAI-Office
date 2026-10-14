import Cocoa
import Darwin
import Foundation

private struct PackageMetadata: Decodable {
    let format: Int
    let kind: String
    let baseVersion: String?
    let targetVersion: String
}

private enum UpdaterError: LocalizedError {
    case invalidArguments
    case parentDidNotExit
    case invalidPackage(String)
    case versionMismatch(expected: String, actual: String)
    case targetVersionMismatch(expected: String, actual: String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "升级助手参数不完整。"
        case .parentDidNotExit: return "原应用没有正常退出，无法安全替换。"
        case .invalidPackage(let message): return "升级包无效：\(message)"
        case .versionMismatch(let expected, let actual): return "当前版本不匹配（需要 \(expected)，实际为 \(actual)）。"
        case .targetVersionMismatch(let expected, let actual): return "升级包版本不匹配（需要 \(expected)，实际为 \(actual)）。"
        case .commandFailed(let command): return "系统操作失败：\(command)"
        }
    }
}

struct MyAIOfficeUpdater {
    static func main() {
        do {
            try applyUpdate()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private static func applyUpdate() throws {
        let arguments = CommandLine.arguments
        guard let pidValue = argument("--pid", in: arguments),
              let pid = Int32(pidValue),
              let appPath = argument("--app", in: arguments),
              let packagePath = argument("--package", in: arguments),
              let targetVersion = argument("--target-version", in: arguments) else {
            throw UpdaterError.invalidArguments
        }

        guard waitForExit(pid: pid, timeout: 30) else {
            throw UpdaterError.parentDidNotExit
        }

        let fileManager = FileManager.default
        let appURL = URL(fileURLWithPath: appPath).standardizedFileURL
        let packageURL = URL(fileURLWithPath: packagePath).standardizedFileURL
        guard fileManager.fileExists(atPath: appURL.path), fileManager.fileExists(atPath: packageURL.path) else {
            throw UpdaterError.invalidPackage("找不到应用或下载的升级包。")
        }

        let extractionURL = fileManager.temporaryDirectory
            .appendingPathComponent("myai-office-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionURL) }
        try run("/usr/bin/ditto", arguments: ["-x", "-k", packageURL.path, extractionURL.path])

        guard let metadataURL = find(named: "metadata.json", under: extractionURL),
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(PackageMetadata.self, from: metadataData),
              metadata.format == 1 else {
            throw UpdaterError.invalidPackage("缺少可识别的 metadata.json。")
        }
        guard metadata.targetVersion == targetVersion else {
            throw UpdaterError.targetVersionMismatch(expected: targetVersion, actual: metadata.targetVersion)
        }

        let currentVersion = try appVersion(at: appURL)
        let stagedURL = appURL.deletingLastPathComponent()
            .appendingPathComponent(".MyAI Office.staged-\(UUID().uuidString).app", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagedURL) }

        if metadata.kind == "delta" {
            guard metadata.baseVersion == currentVersion else {
                throw UpdaterError.versionMismatch(expected: metadata.baseVersion ?? "未知", actual: currentVersion)
            }
            try fileManager.copyItem(at: appURL, to: stagedURL)
            let packageRoot = metadataURL.deletingLastPathComponent()
            try applyDelta(from: packageRoot, to: stagedURL)
        } else if metadata.kind == "full" {
            guard let packagedApp = findAppBundle(named: appURL.lastPathComponent, under: extractionURL) else {
                throw UpdaterError.invalidPackage("完整升级包中没有 MyAI Office.app。")
            }
            try fileManager.copyItem(at: packagedApp, to: stagedURL)
        } else {
            throw UpdaterError.invalidPackage("不支持的升级类型。")
        }

        let stagedVersion = try appVersion(at: stagedURL)
        guard stagedVersion == targetVersion else {
            throw UpdaterError.targetVersionMismatch(expected: targetVersion, actual: stagedVersion)
        }

        let backupURL = appURL.deletingLastPathComponent()
            .appendingPathComponent(".MyAI Office.backup-\(UUID().uuidString).app", isDirectory: true)
        try fileManager.moveItem(at: appURL, to: backupURL)
        do {
            try fileManager.moveItem(at: stagedURL, to: appURL)
        } catch {
            try? fileManager.moveItem(at: backupURL, to: appURL)
            throw error
        }

        try run("/usr/bin/open", arguments: ["-n", appURL.path])
        try? fileManager.removeItem(at: backupURL)
    }

    private static func applyDelta(from packageRoot: URL, to appURL: URL) throws {
        let fileManager = FileManager.default
        let payloadURL = packageRoot.appendingPathComponent("payload", isDirectory: true)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw UpdaterError.invalidPackage("增量包缺少 payload。")
        }

        guard let enumerator = fileManager.enumerator(at: payloadURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            throw UpdaterError.invalidPackage("无法读取增量包内容。")
        }
        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            let relativePath = String(sourceURL.path.dropFirst(payloadURL.path.count + 1))
            let destinationURL = try safeChild(relativePath, under: appURL)
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        let deletedURL = packageRoot.appendingPathComponent("deleted.txt")
        if let deleted = try? String(contentsOf: deletedURL, encoding: .utf8) {
            for path in deleted.split(whereSeparator: \.isNewline).map(String.init) where !path.isEmpty {
                let destinationURL = try safeChild(path, under: appURL)
                try? fileManager.removeItem(at: destinationURL)
            }
        }
    }

    private static func safeChild(_ relativePath: String, under root: URL) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw UpdaterError.invalidPackage("包含不安全的文件路径。")
        }
        return root.appendingPathComponent(relativePath).standardizedFileURL
    }

    private static func appVersion(at appURL: URL) throws -> String {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              let version = plist["CFBundleShortVersionString"] as? String else {
            throw UpdaterError.invalidPackage("无法读取应用版本。")
        }
        return version
    }

    private static func find(named name: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: []) else { return nil }
        return enumerator.lazy.compactMap { $0 as? URL }.first { $0.lastPathComponent == name }
    }

    private static func findAppBundle(named name: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return nil }
        return enumerator.lazy.compactMap { $0 as? URL }.first {
            $0.lastPathComponent == name && $0.pathExtension == "app"
        }
    }

    private static func argument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func waitForExit(pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdaterError.commandFailed(message?.isEmpty == false ? message! : executable)
        }
        return process.terminationStatus
    }

    private static func showError(_ message: String) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "MyAI Office 升级失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.runModal()
            exit(1)
        }
        RunLoop.main.run()
    }
}

MyAIOfficeUpdater.main()
