// Vigil: keeps the Mac awake so agents keep working, while the screen can stay locked.
import AppKit
import IOKit.pwr_mgt
import ServiceManagement

enum Mode: String, CaseIterable {
    case locked   // Mac stays awake; display may sleep and the screen may lock.
    case display  // Mac and display stay awake.

    var title: String { self == .locked ? "Keep Mac Awake while Locked" : "Keep Display On" }
    var subtitle: String { self == .locked ? "Screen can turn off and lock" : "Screen stays on" }
    var assertion: String {
        self == .locked ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
    }
}

// Minutes; 0 means indefinitely.
let durations: [(minutes: Int, title: String)] = [
    (0, "Indefinitely"), (15, "15 Minutes"), (30, "30 Minutes"),
    (60, "1 Hour"), (120, "2 Hours"), (240, "4 Hours"), (480, "8 Hours"),
]

final class Vigil: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var assertionID: IOPMAssertionID = 0
    private var ticker: Timer?

    private var isOn = false
    private var minutes = 0     // Selected duration of the current session.
    private var endDate: Date?  // nil while running indefinitely.

    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .locked }
        set { defaults.set(newValue.rawValue, forKey: "mode"); apply() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading

        // Only an indefinite session resumes after relaunch.
        if defaults.object(forKey: "enabled") as? Bool ?? true { start(minutes: 0) } else { apply() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        release()
    }

    // MARK: Session

    private func start(minutes: Int) {
        isOn = true
        self.minutes = minutes
        endDate = minutes == 0 ? nil : Date().addingTimeInterval(TimeInterval(minutes * 60))
        defaults.set(minutes == 0, forKey: "enabled")
        ticker?.invalidate()
        ticker = endDate == nil ? nil : Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        apply()
    }

    private func stop() {
        isOn = false
        endDate = nil
        defaults.set(false, forKey: "enabled")
        ticker?.invalidate()
        ticker = nil
        apply()
    }

    private func tick() {
        if let endDate, endDate <= Date() { stop() } else { updateButton() }
    }

    // MARK: Power assertion

    private func apply() {
        release()
        if isOn {
            IOPMAssertionCreateWithName(mode.assertion as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Vigil: keep Mac awake" as CFString, &assertionID)
        }
        updateButton()
    }

    private func release() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
    }

    // MARK: Menu bar button

    private let remainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private var remaining: String? {
        endDate.flatMap { remainingFormatter.string(from: max(0, $0.timeIntervalSinceNow)) }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let symbol = !isOn ? "cup.and.saucer" : (mode == .display ? "sun.max.fill" : "cup.and.saucer.fill")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vigil")
        let title = isOn ? remaining.map { " \($0)" } ?? "" : ""
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ])
    }

    private var statusText: String {
        if !isOn { return "Mac can sleep normally" }
        guard let endDate else { return "Awake until turned off" }
        return "Awake until \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Actions

    @objc private func selectMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let newMode = Mode(rawValue: raw) { mode = newMode }
    }

    @objc private func selectDuration(_ sender: NSMenuItem) { start(minutes: sender.tag) }

    @objc private func turnOff() { stop() }

    @objc private func lockScreen() {
        typealias LockFn = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: LockFn.self)()
        } else {
            Process.launchedProcess(launchPath: "/usr/bin/pmset", arguments: ["displaysleepnow"])
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }

    // MARK: Menu (rebuilt on open so states are always current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(withTitle: statusText, action: nil, keyEquivalent: "").isEnabled = false
        if isOn { add(menu, "Turn Off", #selector(turnOff)) }
        menu.addItem(.separator())

        for option in Mode.allCases {
            let item = add(menu, option.title, #selector(selectMode(_:)), on: option == mode)
            item.subtitle = option.subtitle
            item.representedObject = option.rawValue
        }
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: isOn ? "Keep Awake For" : "Start Keeping Awake For"))
        for duration in durations {
            add(menu, duration.title, #selector(selectDuration(_:)), on: isOn && duration.minutes == minutes)
                .tag = duration.minutes
        }
        menu.addItem(.separator())

        add(menu, "Lock Screen", #selector(lockScreen), key: "l")
        add(menu, "Launch at Login", #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, on: Bool = false, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = on ? .on : .off
        return item
    }
}

let app = NSApplication.shared
let delegate = Vigil()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
