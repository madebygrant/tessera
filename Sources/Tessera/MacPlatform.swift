import AppKit
import ApplicationServices
import TesseraCore

// Private, but stable for a decade; Hammerspoon and every tiling manager use it.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

private func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

private func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func axElements(_ value: CFTypeRef?) -> [AXUIElement] {
    (value as? [AnyObject])?.compactMap { axElement($0) } ?? []
}

private func axSet(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) {
    AXUIElementSetAttributeValue(element, attribute as CFString, value)
}

@MainActor
final class MacPlatform: Platform {
    var onEvent: ((PlatformEvent) -> Void)?

    // AX handles behind the WinIDs the engine holds; refreshed on every lookup.
    private var elements: [WinID: AXUIElement] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    // Apps Tessera only placed once (slot move): resize events for the clamp,
    // without app-wide window and title events.
    private var resizeObservers: [pid_t: AXObserver] = [:]
    private var watchedApps: Set<String> = []
    private var notes: [(NotificationCenter, NSObjectProtocol)] = []
    private let keyTap = KeyTap()

    init() {
        keyTap.onEvent = { [weak self] in self?.onEvent?($0) }
        let ws = NSWorkspace.shared.notificationCenter
        listen(ws, NSWorkspace.didLaunchApplicationNotification) { $0.launched($1) }
        listen(ws, NSWorkspace.didActivateApplicationNotification) { $0.onEvent?(.appActivated($0.process($1))) }
        listen(ws, NSWorkspace.didTerminateApplicationNotification) { $0.terminated($1.processIdentifier) }
        let screenNote = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.screensChanged) }
        }
        notes.append((NotificationCenter.default, screenNote))
    }

    private func listen(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (MacPlatform, NSRunningApplication) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                handler(self, app)
            }
        }
        notes.append((center, token))
    }

    private func process(_ app: NSRunningApplication) -> AppProcess {
        AppProcess(pid: app.processIdentifier, name: app.localizedName, bundleID: app.bundleIdentifier)
    }

    // MARK: Screens and permission

    var screens: [ScreenInfo] {
        // Cocoa is bottom-left from the menu-bar screen; AX is top-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        func flip(_ r: NSRect) -> CGRect {
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens.map { ScreenInfo(name: $0.localizedName, frame: flip($0.frame), usable: flip($0.visibleFrame)) }
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: Lookup

    func processName(pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    func processes(named app: String) -> [AppProcess] {
        NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && ($0.localizedName == app || $0.bundleIdentifier == app) }
            .map(process)
    }

    private func axApp(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        // A hung app would otherwise block the main thread for the 6s default.
        AXUIElementSetMessagingTimeout(el, 1.0)
        return el
    }

    private func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success ? id : nil
    }

    private func info(_ el: AXUIElement, _ pid: pid_t) -> WindowInfo? {
        var subrole: CFTypeRef?
        // A closed window's element still yields its id, so check it's alive.
        if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subrole) == .invalidUIElement { return nil }
        guard let id = windowID(el) else { return nil }
        let ref = WinID(pid: pid, id: id)
        elements[ref] = el
        var point = CGPoint.zero
        var size = CGSize.zero
        if let v = axCopy(el, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &point) }
        if let v = axCopy(el, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
        return WindowInfo(
            ref: ref,
            title: axCopy(el, kAXTitleAttribute) as? String ?? "",
            isStandard: (subrole as? String) == kAXStandardWindowSubrole,
            frame: CGRect(origin: point, size: size)
        )
    }

    func windows(pid: Int32) -> [WindowInfo] {
        axElements(axCopy(axApp(pid), kAXWindowsAttribute)).compactMap { info($0, pid) }
    }

    func mainWindow(pid: Int32) -> WindowInfo? {
        axElement(axCopy(axApp(pid), kAXMainWindowAttribute)).flatMap { info($0, pid) }
    }

    func focusedWindow(pid: Int32) -> WindowInfo? {
        axElement(axCopy(axApp(pid), kAXFocusedWindowAttribute)).flatMap { info($0, pid) }
    }

    // The system-wide focused app is where keystrokes go; NSWorkspace's
    // frontmost app lags it just after cmd-Tab and misses non-activating panels.
    func frontmostWindow() -> WindowInfo? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 1.0)
        var pid: pid_t = 0
        if let app = axElement(axCopy(system, kAXFocusedApplicationAttribute)),
           AXUIElementGetPid(app, &pid) == .success {
            return focusedWindow(pid: pid)
        }
        return NSWorkspace.shared.frontmostApplication.flatMap { focusedWindow(pid: $0.processIdentifier) }
    }

    func isFullScreen(_ ref: WinID) -> Bool {
        element(ref).flatMap { axCopy($0, "AXFullScreen") as? Bool } ?? false
    }

    func window(_ ref: WinID) -> WindowInfo? {
        if let el = elements[ref], let found = info(el, ref.pid), found.ref == ref { return found }
        elements[ref] = nil
        return windows(pid: ref.pid).first { $0.ref == ref }
    }

    private func element(_ ref: WinID) -> AXUIElement? {
        window(ref) == nil ? nil : elements[ref]
    }

    // MARK: Actions

    func setFrame(_ ref: WinID, _ r: CGRect) {
        guard let el = element(ref) else { return }
        if (axCopy(el, kAXMinimizedAttribute) as? Bool) == true { axSet(el, kAXMinimizedAttribute, kCFBooleanFalse) }
        // AXEnhancedUserInterface (Chromium) animates every move, so it's off
        // meanwhile. Size, move, size: an app refuses a size that won't fit at
        // the old position.
        let app = axApp(ref.pid)
        let enhanced = (axCopy(app, "AXEnhancedUserInterface") as? Bool) ?? false
        if enhanced { axSet(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        var size = r.size
        var origin = r.origin
        axSet(el, kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
        axSet(el, kAXPositionAttribute, AXValueCreate(.cgPoint, &origin)!)
        axSet(el, kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
        if enhanced { axSet(app, "AXEnhancedUserInterface", kCFBooleanTrue) }
    }

    func setPosition(_ ref: WinID, _ p: CGPoint) {
        guard let el = element(ref) else { return }
        var p = p
        axSet(el, kAXPositionAttribute, AXValueCreate(.cgPoint, &p)!)
    }

    func raise(_ ref: WinID) {
        guard let el = element(ref) else { return }
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    // AXFrontmost works from a background agent, where
    // NSRunningApplication.activate can be refused since macOS 14.
    func focus(_ ref: WinID) {
        guard let el = element(ref) else { return }
        axSet(axApp(ref.pid), kAXFrontmostAttribute, kCFBooleanTrue)
        axSet(el, kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    // MARK: CoreGraphics queries

    private func cgWindows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    private func bounds(_ info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as! CFDictionary? else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    // AX only lists this Space's windows. CoreGraphics sees every Space but,
    // without Screen Recording, no titles, so any off-Space window counts.
    func hasWindowOnOtherSpace(_ app: String) -> Bool {
        let pids = Set(processes(named: app).map(\.pid))
        guard !pids.isEmpty else { return false }
        let seen = Set(pids.flatMap { windows(pid: $0).map(\.ref.id) })
        return cgWindows().contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let number = info[kCGWindowNumber as String] as? CGWindowID, !seen.contains(number),
                  let b = bounds(info)
            else { return false }
            // Skips the tiny utility surfaces some apps keep at layer 0.
            return b.width >= 100 && b.height >= 100
        }
    }

    func hasWindow(pid: Int32, in frame: CGRect) -> Bool {
        cgWindows().contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = bounds(info)
            else { return false }
            return centre(of: b, isIn: frame)
        }
    }

    // MARK: Launching

    private func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { log.error("\(path) failed: \(error.localizedDescription)") }
    }

    func spawn(_ entry: AppEntry) -> Bool {
        if let launch = entry.launch {
            run("/bin/sh", ["-c", launch])
            return true
        }
        if let dir = entry.profileDir {
            run("/usr/bin/open", ["-na", entry.app, "--args", "--profile-directory=\(dir)", "--new-window"])
            return true
        }
        return false
    }

    // On a running app with no windows, `open` sends a reopen, which makes most
    // apps open one.
    func open(_ app: String) {
        let byID = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) != nil
        run("/usr/bin/open", [byID ? "-b" : "-a", app])
    }

    func openNewWindow(pid: Int32) {
        let paths = [["File", "New Window"], ["File", "New window"], ["Shell", "New Window"], ["Window", "New Window"]]
        for path in paths where pressMenuItem(pid: pid, path: path) { return }
        axSet(axApp(pid), kAXFrontmostAttribute, kCFBooleanTrue)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 45, keyDown: down) // n
            e?.flags = .maskCommand
            e?.postToPid(pid)
        }
    }

    private func pressMenuItem(pid: pid_t, path: [String]) -> Bool {
        guard var node = axElement(axCopy(axApp(pid), kAXMenuBarAttribute)) else { return false }
        for (i, title) in path.enumerated() {
            let children = axElements(axCopy(node, kAXChildrenAttribute))
            guard let item = children.first(where: { (axCopy($0, kAXTitleAttribute) as? String) == title }) else {
                return false
            }
            if i == path.count - 1 {
                if (axCopy(item, kAXEnabledAttribute) as? Bool) == false { return false }
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            guard let menu = axElements(axCopy(item, kAXChildrenAttribute)).first else { return false }
            node = menu
        }
        return false
    }

    // MARK: Window events

    func observe(apps: Set<String>) {
        watchedApps = apps
        for app in NSWorkspace.shared.runningApplications where isWatched(app) {
            attach(app.processIdentifier)
        }
    }

    private func isWatched(_ app: NSRunningApplication) -> Bool {
        watchedApps.contains { $0 == app.localizedName || $0 == app.bundleIdentifier }
    }

    // A just-launched app may not answer AX yet, so attaching retries briefly.
    private func launched(_ app: NSRunningApplication) {
        let proc = process(app)
        onEvent?(.appLaunched(proc))
        guard isWatched(app) else { return }
        Task { @MainActor [weak self] in
            for delay in [0.0, 0.3, 1.0, 2.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !app.isTerminated else { return }
                if self.attach(proc.pid) {
                    // A window may have appeared before the observer did.
                    self.onEvent?(.windowsChanged(proc))
                    return
                }
            }
        }
    }

    private func terminated(_ pid: pid_t) {
        for obs in [observers.removeValue(forKey: pid), resizeObservers.removeValue(forKey: pid)].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        elements = elements.filter { $0.key.pid != pid }
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func makeObserver(_ pid: pid_t) -> AXObserver? {
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let platform = Unmanaged<MacPlatform>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { platform.axEvent(element, name) }
        }, &created)
        guard status == .success, let obs = created else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        return obs
    }

    @discardableResult
    private func attach(_ pid: pid_t) -> Bool {
        if observers[pid] != nil { return true }
        guard let obs = resizeObservers[pid] ?? makeObserver(pid) else { return false }
        resizeObservers[pid] = obs
        let app = axApp(pid)
        let added = AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, refcon)
        guard added == .success || added == .notificationAlreadyRegistered else { return false }
        AXObserverAddNotification(obs, app, kAXTitleChangedNotification as CFString, refcon)
        resizeObservers[pid] = nil
        observers[pid] = obs
        return true
    }

    func watchResize(_ ref: WinID) {
        guard let el = elements[ref] else { return }
        let obs = observers[ref.pid] ?? resizeObservers[ref.pid] ?? makeObserver(ref.pid)
        guard let obs else { return }
        if observers[ref.pid] == nil { resizeObservers[ref.pid] = obs }
        AXObserverAddNotification(obs, el, kAXWindowResizedNotification as CFString, refcon)
    }

    private func axEvent(_ element: AXUIElement, _ notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            // Titles often arrive after the window (Helium), and some apps only
            // post title changes on the window itself.
            if let obs = observers[pid] {
                AXObserverAddNotification(obs, element, kAXTitleChangedNotification as CFString, refcon)
            }
            onEvent?(.windowsChanged(process(app)))
        case kAXTitleChangedNotification:
            onEvent?(.windowsChanged(process(app)))
        case kAXWindowResizedNotification:
            if let id = windowID(element) { onEvent?(.windowResized(WinID(pid: pid, id: id))) }
        default:
            break
        }
    }

    // MARK: Storage and alerts

    func savedProfile(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    func saveProfile(_ name: String, _ key: String) { UserDefaults.standard.set(name, forKey: key) }
    func showAlert(_ notice: Notice) { Toasts.show(notice) }

    // Sketchybar's PATH isn't ours, so find the binary rather than run it by name.
    private var barBinaries: [String: String?] = [:]

    // Misses aren't cached, so installing sketchybar later starts the readout.
    private func sketchybar(_ configured: String?) -> String? {
        let key = configured ?? ""
        if let cached = barBinaries[key] { return cached }
        let fm = FileManager.default
        let found: String?
        if let configured {
            let path = (configured as NSString).expandingTildeInPath
            found = fm.isExecutableFile(atPath: path) ? path : nil
            if found == nil && !barMissLogged {
                log.error("sketchybar.bin \(configured, privacy: .public) not found; bar readout off")
                barMissLogged = true
            }
        } else {
            found = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"].first(where: fm.isExecutableFile)
        }
        if found != nil { barBinaries[key] = found }
        return found
    }
    private var barMissLogged = false

    func triggerBar(bin: String?, event: String, fields: [(String, String)]) {
        guard let path = sketchybar(bin) else { return }
        run(path, ["--trigger", event] + fields.map { "\($0.0)=\($0.1)" })
    }

    func watchKeys(_ on: Bool) { on ? keyTap.start() : keyTap.stop() }
    var heldModifiers: Set<Modifier> { KeyTap.held }
    func showOverlay(_ elements: [OverlayElement]) { OverlayWindows.show(elements) }
    func hideOverlay() { OverlayWindows.hide() }
}
