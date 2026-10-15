// Vigil: keeps the Mac awake so agents keep working, while the screen can stay locked.
import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

enum Mode: String, CaseIterable {
    case off
    case system   // Mac stays awake; display may sleep and the screen may be locked.
    case display  // Mac and display stay awake.

    var title: String {
        switch self {
        case .off: return "Off"
        case .system: return "Keep Mac Awake (screen can lock)"
        case .display: return "Keep Mac and Display Awake"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "cup.and.saucer"
        case .system: return "cup.and.saucer.fill"
        case .display: return "sun.max.fill"
        }
    }
}

final class Vigil: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var assertionID: IOPMAssertionID = 0
    private var powerSource: CFRunLoopSource?

    private var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "mode"); apply() }
    }

    private var onlyOnPower: Bool {
        get { defaults.object(forKey: "onlyOnPower") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "onlyOnPower"); apply() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Re-evaluate when switching between charger and battery.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<Vigil>.fromOpaque(ctx).takeUnretainedValue().apply()
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        release()
    }

    // MARK: Power assertion

    private var isOnACPower: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return type == kIOPMACPowerKey
    }

    private var isActive: Bool { mode != .off && (!onlyOnPower || isOnACPower) }

    private func apply() {
        release()
        if isActive {
            let type = mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                                        : kIOPMAssertionTypePreventUserIdleSystemSleep
            IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Vigil: keep Mac awake" as CFString, &assertionID)
        }
        let symbol = isActive ? mode.symbol : Mode.off.symbol
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vigil")
        statusItem.button?.toolTip = isActive ? "Vigil: \(mode.title)" : "Vigil: sleep allowed"
    }

    private func release() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
    }

    // MARK: Lid closed (pmset disablesleep, needs admin)

    private var lidSleepDisabled: Bool {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    @objc private func toggleLid() {
        let value = lidSleepDisabled ? 0 : 1
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    // MARK: Actions

    @objc private func selectMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let newMode = Mode(rawValue: raw) { mode = newMode }
    }

    @objc private func toggleOnlyOnPower() { onlyOnPower.toggle() }

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

        let status = !isActive && mode != .off ? "Paused: on battery" : (isActive ? "Mac will stay awake" : "Mac can sleep")
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        for option in Mode.allCases {
            let item = menu.addItem(withTitle: option.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == mode ? .on : .off
        }
        menu.addItem(.separator())

        add(menu, "Only When on Power Adapter", #selector(toggleOnlyOnPower), on: onlyOnPower)
        add(menu, "Stay Awake With Lid Closed…", #selector(toggleLid), on: lidSleepDisabled)
        add(menu, "Launch at Login", #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())

        let lock = menu.addItem(withTitle: "Lock Screen Now", action: #selector(lockScreen), keyEquivalent: "l")
        lock.target = self
        menu.addItem(withTitle: "Quit Vigil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, on: Bool) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = Vigil()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
