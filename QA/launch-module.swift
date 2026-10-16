import Cocoa

guard CommandLine.arguments.count > 1 else { fatalError("usage: launch-module APP [ARGS...]") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = ProcessInfo.processInfo.environment["MYAI_QA_BACKGROUND"] != "1"
configuration.createsNewApplicationInstance = true
configuration.arguments = Array(CommandLine.arguments.dropFirst(2))
var environment = ProcessInfo.processInfo.environment
environment["MYAI_OFFICE_LANGUAGE"] = "zh-hans"
for name in ["DECKCRAFT_NO_PREFS", "DECKCRAFT_NO_RECOVERY", "WORDCRAFT_NO_PREFS", "WORDCRAFT_NO_RECOVERY", "GRIDCRAFT_NO_PREFS", "MYAI_OFFICE_QA"] {
    environment[name] = "1"
}
configuration.environment = environment
var completed = false
NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
    if let error { fputs("\(error)\n", stderr) }
    if let application { print("PID=\(application.processIdentifier) bundle=\(application.bundleIdentifier ?? "nil")") }
    completed = true
}
let deadline = Date().addingTimeInterval(20)
while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
if !completed { exit(1) }
