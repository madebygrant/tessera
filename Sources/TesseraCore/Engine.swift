import CoreGraphics

public struct Binding {
    public let modifiers: [String]
    public let key: String
    // What the key does, for messages that have to name it.
    public let purpose: String
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
    private(set) var overlay: Overlay?
    public private(set) var profile: String?

    // Entry key -> the window the switcher placed for it; profiles reuse it.
    private var registry: [String: WinID] = [:]
    private var placedAt: [WinID: Double] = [:]
    private var lastAlert: [String: Double] = [:]
    private var lastCycle = -Double.infinity

    nonisolated static let launchTimeout = 5.0
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
        pushToBar(focused: false)
        if config.isOn(config.overlay) {
            overlay = Overlay(engine: self, delay: config.overlay?.delay ?? 1.0)
        }
        platform.watchKeys(overlay != nil)
    }

    public func stop() {
        waits.cancelAll()
        layouts.stop()
        switcher.stop()
        overlay?.stop()
        platform.watchKeys(false)
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
        case let .modifiersChanged(mods):
            overlay?.modifiersChanged(mods)
        case .keyDown:
            overlay?.keyDown()
        }
    }

    // The config's hotkeys, in its order, each given its action. Number keys
    // are bound for the widest list, so a profile switch never rebinds.
    public var bindings: [Binding] {
        var actions: [@MainActor () -> Void] = (0..<config.maxSwitcherApps).map { i in
            { [weak self] in self?.switcher.press(i) }
        }
        actions.append { [weak self] in self?.switcher.step(-1) }
        actions.append { [weak self] in self?.switcher.step(1) }
        actions.append { [weak self] in self?.switcher.toggleMaximize() }
        for name in config.profiles.keys.sorted() {
            actions.append { [weak self] in self?.layouts.apply(name) }
        }
        if config.isOn(config.slotMove), config.keys.slotMove != nil {
            for i in 0..<config.maxSlotMoveKeys {
                actions.append { [weak self] in self?.moveFocused(toSlot: i) }
            }
        }
        return zip(config.hotkeys, actions).map { hotkey, action in
            // Any hotkey is a chord, not a look, even when the tap can't see it.
            Binding(modifiers: hotkey.modifiers, key: hotkey.key, purpose: hotkey.purpose) { [weak self] in
                self?.overlay?.keyDown()
                action()
            }
        }
    }

    // Moves whatever window has focus, so an app Tessera doesn't know about
    // still lands somewhere sane. A key past the active profile's count does nothing.
    func moveFocused(toSlot i: Int) {
        guard let name = profile, let order = config.profiles[name]?.slotOrder, i < order.count,
              let win = platform.frontmostWindow(),
              // A sheet or palette stretched to a slot is never what was meant.
              win.isStandard, !platform.isFullScreen(win.ref)
        else { return }
        place(win.ref, in: frame(ofSlot: order[i]))
    }

    public func apply(profile name: String) { layouts.apply(name) }

    public func previewOverlay() { overlay?.preview() }
    public func switchTo(_ index: Int) { switcher.press(index) }
    public func toggleMaximize() { switcher.toggleMaximize() }

    // What the menu bar menu shows. Chords are key equivalents: the modifiers
    // and one key, which the menu draws the way macOS menus do.
    public struct MenuState {
        public struct Chord {
            public let modifiers: Set<Modifier>
            public let key: String
            public init(modifiers: Set<Modifier>, key: String) {
                self.modifiers = modifiers
                self.key = key
            }
        }
        public struct App {
            public let name: String
            public let chord: Chord?
            public let showing: Bool
            public let running: Bool
        }
        public struct ProfileItem {
            public let id: String
            public let name: String
            public let chord: Chord?
            public let active: Bool
            // False when a screen it needs isn't connected.
            public let fits: Bool
        }
        public let profileName: String?
        public let profileChord: Chord?
        public let screens: [String]
        public let apps: [App]
        public let maximizeChord: Chord?
        public let maximized: Bool
        public let profiles: [ProfileItem]
        public let overlayOn: Bool
    }

    public var menuState: MenuState {
        func chord(_ mods: [String]?, _ key: String) -> MenuState.Chord? {
            guard let mods, let set = try? KeyNames.modifiers(mods) else { return nil }
            return .init(modifiers: set, key: key)
        }
        let sw = config.keys.switcher
        let apps = (switcher.block?.apps ?? []).enumerated().map { i, ref in
            MenuState.App(
                name: prettyName(ref), chord: chord(sw, "\(i + 1)"), showing: i == switcher.index,
                running: config.apps[ref].map { !platform.processes(named: $0.app).isEmpty } ?? false
            )
        }
        let profiles = config.profiles.sorted { ($0.value.key.lowercased(), $0.key) < ($1.value.key.lowercased(), $1.key) }
            .map { id, p in
                MenuState.ProfileItem(id: id, name: prettyName(id), chord: chord(p.modifier ?? config.keys.profile, p.key),
                                      active: id == profile, fits: config.profileFits(id, connected: screenNames))
            }
        let active = profile.flatMap { config.profiles[$0] }
        return MenuState(
            profileName: profile.map(prettyName),
            profileChord: active.flatMap { chord($0.modifier ?? config.keys.profile, $0.key) },
            screens: screenNames, apps: apps, maximizeChord: chord(sw, config.keys.maximize),
            maximized: switcher.maximized, profiles: profiles, overlayOn: overlay != nil
        )
    }

    // From the bar's scroll: a trackpad sends a burst, so one step per 0.4s.
    public func cycle(_ step: Int) {
        let now = scheduler.now
        guard now - lastCycle >= 0.4 else { return }
        lastCycle = now
        switcher.step(step)
    }

    // The bar restarts on its own schedule and asks for the current state.
    public func pushToBar() { pushToBar(focused: false) }

    // `focused` says the switcher just pulled the app forward, which beats
    // waiting on the bar's own front_app event. A retarget focuses nothing.
    func pushToBar(focused: Bool) {
        guard config.isOn(config.sketchybar), let switcher, let block = switcher.block else { return }
        let i = switcher.index
        let current = i < switcher.workspace.count ? switcher.workspace[i] : nil
        platform.triggerBar(bin: config.sketchybar?.bin, event: config.sketchybar?.event ?? "tessera_switcher", fields: [
            ("APP", i < block.apps.count ? block.apps[i] : ""),
            ("INDEX", "\(i + 1)"),
            ("COUNT", "\(block.apps.count)"),
            ("PROFILE", profile ?? ""),
            ("MAXIMIZED", "\(switcher.maximized)"),
            // As macOS reports them, so the bar can match front_app.
            ("APP_NAME", current.map { displayName($0.app) } ?? ""),
            ("ANCHOR_NAME", config.apps[block.anchor].map { displayName($0.app) } ?? ""),
            ("FOCUSED", "\(focused)"),
        ])
    }

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

    // An entry may hold a bundle id; the running process knows its display name.
    func displayName(_ app: String) -> String {
        platform.processes(named: app).lazy.compactMap(\.name).first ?? app
    }

    func frame(ofSlot name: String) -> CGRect { config.frame(ofSlot: name, screens: platform.screens) }
    func usableScreen(ofSlot name: String) -> CGRect? { config.usableScreen(ofSlot: name, screens: platform.screens) }

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

    func launchBlocker(_ app: String) -> Notice? {
        if !platform.isTrusted {
            return Notice("Tessera has no Accessibility permission",
                          "Nothing moves until it's back. Turn it on, then quit and reopen Tessera.",
                          action: .openAccessibilitySettings)
        }
        if platform.hasWindowOnOtherSpace(app) {
            return Notice("\(app) has a window on another Space",
                          "Tessera won't open a second one. Switch to that Space, or close the window there.")
        }
        return nil
    }

    // Errors only, each at most once per 5s: a profile apply can hit the same
    // blocker for every entry.
    func alert(_ notice: Notice) {
        let key = notice.title + "\n" + notice.detail
        let now = scheduler.now
        if let last = lastAlert[key], now - last < 5 { return }
        lastAlert[key] = now
        platform.showAlert(notice)
    }
}
