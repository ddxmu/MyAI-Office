import Cocoa
import Darwin

@main
struct MyAIOfficeUpdater {
    static func main() {
        do {
            if CommandLine.arguments.contains("--prepare-only") {
                try MyAIUpdatePackage.stage(package: url("--package"), base: url("--app"),
                    destination: url("--staged"), targetVersion: required("--target-version"))
                print("PASS: staged application verified")
            } else {
                try install()
            }
        } catch {
            if CommandLine.arguments.contains("--prepare-only") {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "MyAI Office 更新未完成"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
            exit(1)
        }
    }

    private static func install() throws {
        let fm = FileManager.default
        let app = try url("--app")
        let staged = try url("--staged")
        let receipt = try url("--receipt")
        let target = try required("--target-version")
        guard let pid = Int32(try required("--pid")), pid > 1,
              staged.deletingLastPathComponent() == app.deletingLastPathComponent(),
              staged.lastPathComponent.hasPrefix(".MyAI Office.staged-"),
              MyAIUpdateReceipt.isOwned(receipt) else { throw MyAIUpdatePackage.Invalid("安装参数无效。") }
        guard try MyAIUpdatePackage.version(app) == required("--base-version"),
              try MyAIUpdatePackage.version(staged) == target else {
            throw MyAIUpdatePackage.Invalid("安装版本发生变化，请重新检查更新。")
        }
        try MyAIUpdatePackage.verifySignature(staged)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.2) }
        guard kill(pid, 0) != 0, errno == ESRCH else {
            throw MyAIUpdatePackage.Invalid("原应用尚未退出，未替换任何文件。")
        }

        let backup = app.deletingLastPathComponent()
            .appendingPathComponent(".MyAI Office.backup-\(UUID().uuidString).app")
        try fm.moveItem(at: app, to: backup)
        do {
            try fm.moveItem(at: staged, to: app)
            var arguments = ["-n", app.path]
            if ProcessInfo.processInfo.environment["MYAI_OFFICE_QA"] == "1" {
                arguments += ["--env", "MYAI_OFFICE_QA=1"]
            }
            arguments += ["--args", "--myai-update-result", receipt.path]
            try MyAIUpdatePackage.run("/usr/bin/open", arguments)
        } catch {
            if fm.fileExists(atPath: app.path) { try fm.moveItem(at: app, to: staged) }
            try fm.moveItem(at: backup, to: app)
            _ = try? MyAIUpdatePackage.run("/usr/bin/open", ["-n", app.path])
            throw MyAIUpdatePackage.Invalid("新版本未能启动，已恢复原版本。\n\(error.localizedDescription)")
        }

        // Retain the rollback copy until the new application confirms it has launched.
        let launchDeadline = Date().addingTimeInterval(40)
        while Date() < launchDeadline {
            if let result = try? MyAIUpdateReceipt.read(receipt), result.state == "success",
               result.targetVersion == target, result.appPath == app.path {
                try? fm.removeItem(at: backup)
                try? fm.removeItem(at: receipt)
                if let package = optional("--package") { try? fm.removeItem(atPath: package) }
                let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
                if executable.deletingLastPathComponent().lastPathComponent.hasPrefix("myai-installer-") {
                    try? fm.removeItem(at: executable.deletingLastPathComponent())
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw MyAIUpdatePackage.Invalid("新版本未确认启动。为保护文件，原版本已保留在：\n\(backup.path)")
    }

    private static func optional(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func required(_ flag: String) throws -> String {
        guard let value = optional(flag) else { throw MyAIUpdatePackage.Invalid("缺少参数：\(flag)") }
        return value
    }

    private static func url(_ flag: String) throws -> URL {
        URL(fileURLWithPath: try required(flag)).standardizedFileURL.resolvingSymlinksInPath()
    }
}
