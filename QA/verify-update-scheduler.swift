import Cocoa

@main
struct VerifyUpdateScheduler {
    static func main() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        func automatic(_ enabled: Bool) {
            var arguments = original
            arguments["MyAIAutomaticUpdateChecks"] = enabled
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        let manager = MyAIOfficeUpdateManager.shared
        var events = 0
        manager.observe { _ in events += 1 }
        automatic(false)
        manager.startAutomaticChecks(presenting: nil)
        func timer() -> Timer {
            let optional = Mirror(reflecting: manager).children.first { $0.label == "timer" }!.value
            return Mirror(reflecting: optional).children.first!.value as! Timer
        }
        let first = timer()
        precondition(first.isValid && first.timeInterval == 14400)
        precondition(abs(first.fireDate.timeIntervalSinceNow - 14400) < 3)
        let initialEvents = events
        first.fire()
        precondition(events == initialEvents, "Disabled automatic checking still made a request")
        automatic(true)
        first.fire()
        // This unbundled test tool has no manifest URL: reaching that failure proves the timer called the checker.
        guard case .failed(let message) = manager.state, message == "未配置更新地址。" else { fatalError("Timer did not invoke checking") }
        automatic(false)
        manager.startAutomaticChecks(presenting: nil)
        precondition(!first.isValid && timer().isValid, "Restarting checks created duplicate timers")
        print("PASS: real 4-hour Timer, disabled/enabled dispatch and duplicate-timer prevention; no persisted settings changed")
    }
}
