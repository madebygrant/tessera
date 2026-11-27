import CoreGraphics

public struct Binding {
    public let modifiers: [String]
    public let key: String
    public let action: @MainActor () -> Void
}

// One loaded config's worth of state. Reloading builds a new one.
@MainActor
public final class Engine {
    public let config: Config
    let platform: Platform
    let scheduler: Scheduler
    let waits: Waits
    private(set) var switcher: Switcher!
    private(set) var layouts: Layouts!
    public private(set) var profile: String?

    // Entry key -> the window the switcher placed for it; profiles reuse it.
    private var registry: [String: WinID] = [:]
    private var placedAt: [WinID: Double] = [:]
    private var lastAlert: [String: Double] = [:]

    static let launchTimeout = 5.0
    // An app's own resize this soon after a placement gets clamped (Ghostty
    // snapping to its cell grid); later ones are the user's.
    static let clampWindow = 1.0

    public init(config: Config, platform: Platform, scheduler: Scheduler) {
        self.config = config
        self.platform = platform
        self.scheduler = scheduler
        waits = Waits(scheduler: scheduler)
        platform.observe(apps: Set(config.apps.values.map(\.app)))
        layouts = Layouts(engine: self)
        let start = config.bestProfile(saved: savedProfile, connected: screenNames)
        switcher = Switcher(engine: self, startProfile: start)
    }

    public func stop() {
        waits.cancelAll()
        layouts.stop()
        switcher.stop()
    }

    public func handle(_ event: PlatformEvent) {
        switch event {
        case let .appLaunched(p):
            switcher.appLaunched(p)
            waits.appChanged(p)
        case let .appActivated(p):
            switcher.activated(p)
        case let .windowsChanged(p):
            waits.appChanged(p)
        case let .windowResized(ref):
            if let at = placedAt[ref], scheduler.now - at <= Self.clampWindow { clamp(ref) }
        case .screensChanged:
            layouts.screensChanged()
        }
    }

    public var bindings: [Binding] {
        let mods = config.keys.switcher
        // Bound for the widest list, so a profile switch never rebinds.
        var out = (0..<config.maxSwitcherApps).map { i in
            Binding(modifiers: mods, key: "\(i + 1)") { [weak self] in self?.switcher.press(i) }
        }
        out.append(Binding(modifiers: mods, key: "left") { [weak self] in self?.switcher.step(-1) })
        out.append(Binding(modifiers: mods, key: "right") { [weak self] in self?.switcher.step(1) })
        out.append(Binding(modifiers: mods, key: config.keys.maximize) { [weak self] in self?.switcher.toggleMaximize() })
        for (name, p) in config.profiles.sorted(by: { $0.key < $1.key }) {
            out.append(Binding(modifiers: p.modifier ?? config.keys.profile ?? [], key: p.key) { [weak self] in
                self?.layouts.apply(name)
            })
        }
        return out
    }

    public func apply(profile name: String) { layouts.apply(name) }

    public var status: [String] {
        ["Profile \(profile ?? "none")"] + switcher.status
    }

    // MARK: Profile state

    var screenNames: [String] { platform.screens.map(\.name) }

    // Per screen setup, so undocking and re-docking each return to the last
    // profile used with those screens.
    public static func profileKey(_ screenNames: [String]) -> String {
        "profile." + screenNames.sorted().joined(separator: "|")
    }

    var savedProfile: String? { platform.savedProfile(Self.profileKey(screenNames)) }

    // Same-name calls are ignored, so re-pressing the active profile's key
    // re-places windows without resetting the switcher.
    func setProfile(_ name: String) {
        guard name != profile else { return }
        profile = name
        platform.saveProfile(name, Self.profileKey(screenNames))
        switcher?.useProfile(name, apply: false)
    }

    func applied(_ name: String) { switcher.profileApplied() }

    // MARK: Windows

    func publish(_ key: String, _ ref: WinID) { registry[key] = ref }

    func trackedWindow(_ key: String) -> WindowInfo? {
        registry[key].flatMap { platform.window($0) }
    }

    func frame(ofSlot name: String) -> CGRect { config.frame(ofSlot: name, screens: platform.screens) }

    func standardWindows(_ app: String) -> [WindowInfo] {
        platform.processes(named: app).flatMap { platform.windows(pid: $0.pid).filter(\.isStandard) }
    }

    // The process with the most standard windows; a stray second instance has few.
    func primaryProcess(_ app: String) -> AppProcess? {
        platform.processes(named: app)
            .map { ($0, platform.windows(pid: $0.pid).filter(\.isStandard).count) }
            .max { $0.1 < $1.1 }?.0
    }

    func place(_ ref: WinID, in frame: CGRect) {
        platform.setFrame(ref, frame)
        clamp(ref)
        let now = scheduler.now
        placedAt = placedAt.filter { now - $0.value <= Self.clampWindow }
        placedAt[ref] = now
        platform.watchResize(ref)
        // Backstop for an app that resizes without posting AXWindowResized.
        scheduler.after(0.5) { [weak self] in self?.clamp(ref) }
    }

    // Right edge only, so a window can't bleed onto the next screen. Falling off
    // the bottom beats overlapping the slot above.
    func clamp(_ ref: WinID) {
        guard let f = platform.window(ref)?.frame,
              let s = usableFrame(containing: f, screens: platform.screens),
              f.maxX > s.maxX
        else { return }
        platform.setPosition(ref, CGPoint(x: s.maxX - f.width, y: f.minY))
    }

    // MARK: Errors

    func launchBlocker(_ app: String) -> String? {
        if !platform.isTrusted {
            return "Tessera has no Accessibility permission. Enable it in System Settings"
        }
        if platform.hasWindowOnOtherSpace(app) {
            return "\(app) has a window on another Space; not opening another"
        }
        return nil
    }

    // Errors only, each at most once per 5s: a profile apply can hit the same
    // blocker for every entry.
    func alert(_ message: String) {
        let now = scheduler.now
        if let last = lastAlert[message], now - last < 5 { return }
        lastAlert[message] = now
        platform.showAlert(message)
    }
}
