// Vigil: keeps the Mac awake so agents keep working, while the screen can stay locked.
import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

final class Vigil: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var assertionID: IOPMAssertionID = 0
    private var powerSource: CFRunLoopSource?

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled"); apply() }
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

    // Only holds the Mac awake on the charger; the display may still sleep and the screen may lock.
    private func apply() {
        release()
        let active = enabled && isOnACPower
        if active {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Vigil: keep Mac awake" as CFString, &assertionID)
        }
        statusItem.button?.image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer",
                                           accessibilityDescription: "Vigil")
    }

    private func release() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
    }

    // MARK: Actions

    @objc private func toggleEnabled() { enabled.toggle() }

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
        add(menu, "Keep Mac Awake", #selector(toggleEnabled), on: enabled)
        add(menu, "Lock Screen", #selector(lockScreen), key: "l")
        menu.addItem(.separator())
        add(menu, "Launch at Login", #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, on: Bool = false, key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = on ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = Vigil()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
