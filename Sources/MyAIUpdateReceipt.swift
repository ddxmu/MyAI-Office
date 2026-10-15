import Foundation

struct MyAIUpdateReceipt: Codable {
    let targetVersion: String
    let appPath: String
    var state: String

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyAI Office/Updates", isDirectory: true)
    }

    static func isOwned(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath()
            && url.pathExtension == "json" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }

    static func read(_ url: URL) throws -> MyAIUpdateReceipt {
        guard isOwned(url) else { throw MyAIUpdatePackage.Invalid("无效的更新回执路径。") }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func write(_ url: URL) throws {
        guard Self.isOwned(url) else { throw MyAIUpdatePackage.Invalid("无效的更新回执路径。") }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
