// Pins the active profile's anchor to one slot and cycles its other apps
// through a second.
@MainActor
final class Switcher {
    private unowned let engine: Engine
    private var config: Config { engine.config }
    private var platform: Platform { engine.platform }

    private(set) var block: SwitcherBlock!
    private var anchor: AppEntry!
    private(set) var workspace: [AppEntry] = []
    private(set) var index = 0
    private(set) var maximized = false
    // One wait per entry, so rapid re-switches don't race to place one window.
    private var pending: [String: Cancellable] = [:]

    init(engine: Engine, startProfile: String) {
        self.engine = engine
        // Before this switcher is assigned, so it's recorded without a retarget
        // and pressing the profile's own key later re-places only.
        engine.setProfile(startProfile)
        useProfile(startProfile, apply: true)
    }

    func stop() { cancelPending() }

    var status: [String] {
        var lines = [
            "Index \(index + 1)/\(workspace.count)" + (maximized ? " (maximized)" : ""),
            "Anchor \(anchor?.app ?? "none")",
        ]
        if !pending.isEmpty {
            lines.append("Waiting on " + pending.keys.map { $0.replacingOccurrences(of: "\0", with: "/") }.sorted().joined(separator: ", "))
        }
        for (i, entry) in workspace.enumerated() {
            let win = engine.trackedWindow(entry.key)
            lines.append("\(i + 1). \(entry.app): " + (win.map { "\($0.ref) \($0.title)" } ?? "no window tracked"))
        }
        return lines
    }

    // MARK: Window lookup

    private func titledWindow(_ app: String, _ suffix: String) -> WindowInfo? {
        engine.standardWindows(app).first { $0.title.hasSuffix(suffix) }
    }

    // For an untitled entry: any window a titled sibling hasn't claimed, main
    // windows first since AX order across processes means nothing.
    private func plainWindow(_ app: String) -> WindowInfo? {
        let reserved = config.reservedSuffixes(app)
        func claimable(_ w: WindowInfo) -> Bool {
            w.isStandard && !reserved.contains { w.title.hasSuffix($0) }
        }
        var fallback: WindowInfo?
        for p in platform.processes(named: app) {
            if let main = platform.mainWindow(pid: p.pid), claimable(main) { return main }
            if fallback == nil { fallback = platform.windows(pid: p.pid).first(where: claimable) }
        }
        return fallback
    }

    // Adopting matters after a reboot: the registry is empty and an app opened
    // at login already has its window.
    private func existingWindow(_ entry: AppEntry, remember: Bool) -> WindowInfo? {
        if let suffix = entry.titleSuffix { return titledWindow(entry.app, suffix) }
        return (remember ? engine.trackedWindow(entry.key) : nil) ?? plainWindow(entry.app)
    }

    // MARK: Placement

    // Never opens a second window; only the profile applier does that.
    private func placeApp(_ entry: AppEntry, _ slot: String, remember: Bool = false, focus: Bool = true, adoptOnly: Bool = false) {
        let key = entry.key
        let win = existingWindow(entry, remember: remember)
        // Before cancelling, so a no-op call leaves a launch in flight alone.
        if win == nil && adoptOnly { return }
        pending.removeValue(forKey: key)?.cancel()

        let land = { [weak self] (w: WindowInfo) in
            guard let self else { return }
            self.engine.place(w.ref, in: self.engine.frame(ofSlot: slot))
            if focus { self.platform.focus(w.ref) }
            if remember || entry.titleSuffix != nil { self.engine.publish(key, w.ref) }
        }
        if let win { return land(win) }

        if let blocked = engine.launchBlocker(entry.app) { return engine.alert(blocked) }
        if !platform.spawn(entry) { platform.open(entry.app) }
        pending[key] = engine.waits.start(app: entry.app, timeout: Engine.launchTimeout, check: { [weak self] in
            guard let self, let w = self.existingWindow(entry, remember: false) else { return false }
            self.pending[key] = nil
            land(w)
            return true
        }, onTimeout: { [weak self] in
            self?.pending[key] = nil
            self?.engine.alert("no window from \(entry.app) after \(Int(Engine.launchTimeout))s")
        })
    }

    private func cancelPending() {
        for wait in pending.values { wait.cancel() }
        pending = [:]
    }

    // Retargets only; the profile applier places windows. At load it places
    // too, without focus, so starting Tessera doesn't steal focus.
    func useProfile(_ name: String, apply: Bool) {
        guard let profile = config.profiles[name] else { return }
        // A launch still chasing the old profile would land in its slots.
        cancelPending()
        block = profile.switcher
        anchor = config.apps[block.anchor]
        workspace = block.apps.compactMap { config.apps[$0] }
        index = block.startIndex
        maximized = false
        guard apply else { return }
        let adoptOnly = config.launchAtLoad == false
        placeApp(anchor, block.anchorSlot, focus: false, adoptOnly: adoptOnly)
        if index < workspace.count {
            placeApp(workspace[index], block.otherSlot, remember: true, focus: false, adoptOnly: adoptOnly)
        }
    }

    // A key past the active profile's count does nothing.
    func press(_ i: Int) {
        if i < workspace.count { switchTo(i) }
    }

    func step(_ delta: Int) { switchTo(index + delta) }

    // A cycled app still launching would land and take focus from the one just
    // picked. The anchor's launch stays: retrying it could fork a second instance.
    private func cancelCycledLaunches() {
        for (key, wait) in pending where key != anchor.key {
            wait.cancel()
            pending[key] = nil
        }
    }

    func switchTo(_ i: Int) {
        let count = workspace.count
        guard count > 0 else { return }
        cancelCycledLaunches()
        index = (i % count + count) % count
        maximized = false
        // Anchor first and without focus, so the switched-to app ends up focused.
        placeApp(anchor, block.anchorSlot, focus: false)
        placeApp(workspace[index], block.otherSlot, remember: true)
    }

    func toggleMaximize() {
        guard index < workspace.count else { return }
        let entry = workspace[index]
        maximized.toggle()
        if maximized {
            placeApp(entry, block.fullSlot, remember: true)
        } else {
            placeApp(anchor, block.anchorSlot, focus: false)
            placeApp(entry, block.otherSlot, remember: true)
        }
    }

    // The profile applier stacks every cycled app in one slot without raising
    // any, so put the current one on top.
    func profileApplied() {
        maximized = false
        guard index < workspace.count, let w = existingWindow(workspace[index], remember: true) else { return }
        platform.raise(w.ref)
    }

    // Adopt only, never launch: this fires for processes our own `open -na`
    // spawns too. A launch already in flight places the window itself.
    func appLaunched(_ p: AppProcess) {
        guard let anchor, p.matches(anchor.app), pending[anchor.key] == nil else { return }
        let key = anchor.key
        let slot = block.anchorSlot
        pending[key] = engine.waits.start(app: anchor.app, timeout: Engine.launchTimeout, check: { [weak self] in
            guard let self, let w = self.existingWindow(anchor, remember: false) else { return false }
            self.pending[key] = nil
            self.engine.place(w.ref, in: self.engine.frame(ofSlot: slot))
            return true
        }, onTimeout: { [weak self] in self?.pending[key] = nil })
    }

    // Activating an app raises ALL its windows, so Helium's other profile can
    // cover the slot. Raise the slot's own window back; focus stays put.
    func activated(_ p: AppProcess) {
        guard index < workspace.count else { return }
        let entry = workspace[index]
        if p.matches(entry.app) { return }

        let slot = engine.frame(ofSlot: maximized ? block.fullSlot : block.otherSlot)
        // CoreGraphics first: an AX call into a hung app blocks until timeout.
        guard platform.hasWindow(pid: p.pid, in: slot) else { return }
        guard let tracked = engine.trackedWindow(entry.key), centre(of: tracked.frame, isIn: slot) else { return }

        // If the window they activated is itself in the slot, they chose it.
        let focused = platform.focusedWindow(pid: p.pid)
        if let focused, centre(of: focused.frame, isIn: slot) { return }
        let intruder = platform.windows(pid: p.pid).contains {
            $0.isStandard && $0.ref != focused?.ref && centre(of: $0.frame, isIn: slot)
        }
        if intruder { platform.raise(tracked.ref) }
    }
}
