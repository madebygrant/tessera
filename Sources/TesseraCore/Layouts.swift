// Applies a profile: each `place` entry's app into its slot.
@MainActor
final class Layouts {
    private unowned let engine: Engine
    private var config: Config { engine.config }
    private var current: Apply?
    private var lastRun: [String: Double] = [:]
    private var screenTimer: Cancellable?
    // Absorbs a double-tap without swallowing a real bounce between profiles.
    static let debounce = 2.0

    private final class Apply {
        let name: String
        let launch: Bool
        var outstanding: Int
        var used: Set<WinID> = []
        var waits: [Cancellable] = []
        init(name: String, launch: Bool, outstanding: Int) {
            self.name = name
            self.launch = launch
            self.outstanding = outstanding
        }
    }

    init(engine: Engine) { self.engine = engine }

    func stop() {
        screenTimer?.cancel()
        cancel()
    }

    // For undo too: a late window would land in the undone layout, and the
    // debounce would swallow pressing that profile's key again.
    func cancel() {
        current?.waits.forEach { $0.cancel() }
        current = nil
        lastRun = [:]
    }

    // A dock or undock fires several events; act once they stop. Never launches.
    func screensChanged() {
        screenTimer?.cancel()
        screenTimer = engine.scheduler.after(1) { [weak self] in
            guard let self else { return }
            let name = self.config.bestProfile(saved: self.engine.savedProfile, current: self.engine.profile, connected: self.engine.screenNames)
            self.lastRun[name] = nil
            self.apply(name, launch: false)
        }
    }

    func apply(_ name: String, launch: Bool = true) {
        guard let profile = config.profiles[name] else { return }
        let now = engine.scheduler.now
        if let last = lastRun[name], now - last < Self.debounce { return }
        lastRun[name] = now
        if launch { engine.beginUndo() }
        // Retarget the switcher first, so its slots match this layout.
        engine.setProfile(name)
        // A late window from the previous apply must not land in its layout.
        current?.waits.forEach { $0.cancel() }
        let place = profile.place ?? []
        let run = Apply(name: name, launch: launch, outstanding: place.count)
        current = run
        for item in place { placeEntry(item, run) }
        if place.isEmpty { engine.applied(name) }
    }

    private func settle(_ run: Apply) {
        run.outstanding -= 1
        if run.outstanding == 0 && run === current { engine.applied(run.name) }
    }

    private func placeEntry(_ item: Placement, _ run: Apply) {
        guard let entry = config.apps[item.app] else { return settle(run) }
        if tryPlace(item, entry, run) { return settle(run) }
        // A screen-change re-apply only moves what exists.
        guard run.launch else { return settle(run) }
        if let blocked = engine.launchBlocker(entry.app) {
            engine.alert(blocked)
            return settle(run)
        }
        launch(entry)
        run.waits.append(engine.waits.start(app: entry.app, timeout: Engine.launchTimeout, check: { [weak self] in
            guard let self, self.tryPlace(item, entry, run) else { return false }
            self.settle(run)
            return true
        }, onTimeout: { [weak self] in
            self?.engine.alert(.noWindow(entry.app))
            self?.settle(run)
        }))
    }

    // With nothing tracked yet this falls through to findWindow, which adopts
    // before launching, so still no duplicate.
    private func tryPlace(_ item: Placement, _ entry: AppEntry, _ run: Apply) -> Bool {
        let tracked = item.useSwitcherWindow == true
            ? engine.trackedWindow(entry.key).flatMap { run.used.contains($0.ref) ? nil : $0 }
            : nil
        guard let win = tracked ?? findWindow(entry, run.used) else { return false }
        engine.place(win.ref, in: engine.frame(ofSlot: item.slot))
        run.used.insert(win.ref)
        return true
    }

    // First unused window. Without a suffix, skip windows a titled sibling claims.
    private func findWindow(_ entry: AppEntry, _ used: Set<WinID>) -> WindowInfo? {
        let reserved = entry.titleSuffix == nil ? config.reservedSuffixes(entry.app) : []
        return engine.standardWindows(entry.app).first { w in
            guard !used.contains(w.ref) else { return false }
            if let suffix = entry.titleSuffix { return w.title.hasSuffix(suffix) }
            return !reserved.contains { w.title.hasSuffix($0) }
        }
    }

    // Running with every window taken (same app in two slots): `open` would
    // just focus one of those, so ask for a new window.
    private func launch(_ entry: AppEntry) {
        if engine.platform.spawn(entry) { return }
        if let running = engine.primaryProcess(entry.app) {
            engine.platform.openNewWindow(pid: running.pid)
        } else {
            engine.platform.open(entry.app)
        }
    }
}
