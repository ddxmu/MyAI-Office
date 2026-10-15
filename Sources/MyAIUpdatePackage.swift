import Foundation
import CryptoKit

enum MyAIUpdatePackage {
    struct Invalid: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }

    private struct Entry: Decodable {
        let path: String
        let sha256: String
        let mode: Int
        let size: Int
    }

    private struct Operation: Decodable {
        let path: String
        let kind: String
        let source: String
        let baseSHA256: String?
    }

    private struct Metadata: Decodable {
        let format: Int
        let kind: String
        let baseVersion: String?
        let targetVersion: String
        let files: [Entry]?
        let operations: [Operation]?
        let deleted: [String]?
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func version(_ app: URL) throws -> String {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard let value = plist?["CFBundleShortVersionString"] as? String else {
            throw Invalid("无法读取应用版本。")
        }
        return value
    }

    static func child(_ path: String, under root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\"), !path.contains("\n") else {
            throw Invalid("升级包包含不安全的文件路径。")
        }
        let url = root.appendingPathComponent(path)
        guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw Invalid("升级路径超出应用目录。")
        }
        return url
    }

    /// All work happens in a sibling staging bundle; the installed app stays untouched.
    static func stage(package: URL, base: URL, destination: URL, targetVersion: String) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw Invalid("暂存路径已存在。") }
        let extraction = fm.temporaryDirectory.appendingPathComponent("myai-package-\(UUID().uuidString)")
        try fm.createDirectory(at: extraction, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extraction) }
        do {
            let listing = try run("/usr/bin/unzip", ["-Z1", package.path])
            for entry in listing.split(whereSeparator: \.isNewline) {
                let path = entry.hasSuffix("/") ? String(entry.dropLast()) : String(entry)
                _ = try child(path, under: extraction)
            }
            try run("/usr/bin/ditto", ["-x", "-k", package.path, extraction.path])
            _ = try regularFiles(extraction)
            let metadata = try JSONDecoder().decode(Metadata.self,
                from: Data(contentsOf: extraction.appendingPathComponent("metadata.json")))
            guard metadata.targetVersion == targetVersion else { throw Invalid("升级包目标版本不匹配。") }
            if metadata.kind == "full", metadata.format == 1 {
                let app = extraction.appendingPathComponent("MyAI Office.app")
                guard fm.fileExists(atPath: app.path) else { throw Invalid("完整包中没有应用。") }
                try fm.copyItem(at: app, to: destination)
            } else {
                guard metadata.baseVersion == (try version(base)) else {
                    throw Invalid("增量包与当前版本不匹配，请使用完整更新包。")
                }
                try fm.copyItem(at: base, to: destination)
                if metadata.format == 2, metadata.kind == "bsdiff" {
                    try applyBinary(metadata, root: extraction, app: destination)
                } else if metadata.format == 1, metadata.kind == "delta" {
                    try applyLegacy(root: extraction, app: destination)
                } else {
                    throw Invalid("无法识别升级包类型。")
                }
            }
            guard try version(destination) == targetVersion else { throw Invalid("重建后的应用版本不匹配。") }
            try verifySignature(destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    private static func applyBinary(_ metadata: Metadata, root: URL, app: URL) throws {
        guard let entries = metadata.files, let operations = metadata.operations, let deleted = metadata.deleted,
              Set(entries.map(\.path)).count == entries.count,
              Set(operations.map(\.path)).count == operations.count else { throw Invalid("增量清单不完整。") }
        let fm = FileManager.default
        let expected = Set(entries.map(\.path))
        for operation in operations {
            guard expected.contains(operation.path) else { throw Invalid("文件不在目标清单内。") }
            let destination = try child(operation.path, under: app)
            let source = try child(operation.source, under: root)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if operation.kind == "patch" {
                guard let hash = operation.baseSHA256, try sha256(destination) == hash else {
                    throw Invalid("当前应用文件已变更，无法应用差分；可改用完整更新包。")
                }
                let patched = root.appendingPathComponent("patched-\(UUID().uuidString)")
                try run("/usr/bin/bspatch", [destination.path, patched.path, source.path])
                try fm.removeItem(at: destination)
                try fm.moveItem(at: patched, to: destination)
            } else if operation.kind == "replace" {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: source, to: destination)
            } else {
                throw Invalid("无法识别差分操作。")
            }
        }
        for path in deleted {
            guard !expected.contains(path) else { throw Invalid("删除清单与目标文件冲突。") }
            let url = try child(path, under: app)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
        let actual = try Set(regularFiles(app).keys)
        guard actual == expected else {
            let missing = expected.subtracting(actual).sorted().prefix(3).joined(separator: "、")
            let extra = actual.subtracting(expected).sorted().prefix(3).joined(separator: "、")
            throw Invalid("重建后的应用文件清单不匹配。缺少：\(missing)；额外：\(extra)")
        }
        for entry in entries {
            let url = try child(entry.path, under: app)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard (0...0o777).contains(entry.mode), (attributes[.size] as? NSNumber)?.intValue == entry.size,
                  try sha256(url) == entry.sha256 else { throw Invalid("文件校验失败：\(entry.path)") }
            try fm.setAttributes([.posixPermissions: entry.mode], ofItemAtPath: url.path)
        }
    }

    private static func applyLegacy(root: URL, app: URL) throws {
        let fm = FileManager.default
        let payload = root.appendingPathComponent("payload")
        guard fm.fileExists(atPath: payload.path) else { throw Invalid("增量包缺少文件内容。") }
        for (path, source) in try regularFiles(payload) {
            let destination = try child(path, under: app)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        }
        let deleted = try String(contentsOf: root.appendingPathComponent("deleted.txt"), encoding: .utf8)
        for path in deleted.split(whereSeparator: \.isNewline) {
            let url = try child(String(path), under: app)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }

    static func regularFiles(_ root: URL) throws -> [String: URL] {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else {
            throw Invalid("无法读取升级文件。")
        }
        var files: [String: URL] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw Invalid("升级包中不允许符号链接。") }
            if values.isRegularFile == true {
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(canonicalRoot.path + "/") else { throw Invalid("无法确定文件的相对路径。") }
                files[String(path.dropFirst(canonicalRoot.path.count + 1))] = url
            }
        }
        return files
    }

    static func verifySignature(_ app: URL) throws {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw Invalid("系统操作失败：\(text.suffix(1200))") }
        return text
    }
}
