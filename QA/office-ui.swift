import Cocoa
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &result)
    return result
}

func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 25 else { return [] }
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [element] + children.flatMap { descendants($0, depth: depth + 1) }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { exit(2) }
let action = arguments[1]
if action == "find" {
    let path = URL(fileURLWithPath: arguments[2]).standardizedFileURL.resolvingSymlinksInPath().path
    let pids = NSWorkspace.shared.runningApplications.filter {
        $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path && !$0.isTerminated
    }.map(\.processIdentifier)
    print(String(decoding: try JSONEncoder().encode(pids), as: UTF8.self))
    exit(0)
}
guard let pid = Int32(arguments[2]) else { exit(2) }
if action == "quit" {
    guard let app = NSRunningApplication(processIdentifier: pid) else { exit(0) }
    app.terminate()
    exit(0)
}
guard AXIsProcessTrusted() else { fputs("Accessibility permission is required\n", stderr); exit(3) }
let root = AXUIElementCreateApplication(pid)
let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
let elements = windows.flatMap { descendants($0) }
if action == "inspect" {
    let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute]
    let rows: [[String: String]] = elements.map { element in
        var row: [String: String] = [:]
        for key in keys { if let value = attribute(element, key) { row[key] = String(describing: value) } }
        return row
    }
    print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
} else if action == "press", arguments.count == 4 {
    let wanted = arguments[3]
    guard let button = elements.first(where: { element in
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].contains { key in
            attribute(element, key) as? String == wanted
        }
    }), AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { exit(4) }
} else if action == "capture", arguments.count == 4 {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    guard let window = owned.max(by: {
        func area(_ row: [String: Any]) -> Double {
            let rect = row[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return (rect["Width"] ?? 0) * (rect["Height"] ?? 0)
        }
        return area($0) < area($1)
    }), let number = window[kCGWindowNumber as String] as? Int else { exit(5) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l", String(number), arguments[3]]
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} else { exit(2) }
