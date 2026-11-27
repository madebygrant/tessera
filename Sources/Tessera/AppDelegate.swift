import AppKit
import Carbon
import ServiceManagement
import TesseraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let platform = MacPlatform()
    private let scheduler = MainScheduler()
    private let hotkeys = Hotkeys()
    private let control = Control.Server()
    private var engine: Engine?
    private var statusItem: NSStatusItem!
    private var axTimer: Timer?
    private var axWarned = false
    private var configWatcher: ConfigWatcher?
    // Hotkey problems already shown this session, so a rebind doesn't repeat them.
    private var warnedHotkeys: Set<String> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        platform.onEvent = { [weak self] in self?.engine?.handle($0) }
        control.handler = { [weak self] command, payload in self?.handle(command, payload) ?? "" }
        control.start()
        // Prompts once; macOS remembers the grant per signing identity.
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        statusItem.button?.image = StatusIcon.make(attention: !trusted)
        Toasts.anchor = { [weak self] in self?.statusItem.button?.window?.frame }
        ProfileImport.run()
        let watcher = ConfigWatcher(url: ConfigFile.url)
        watcher.onChange = { [weak self] in self?.start() }
        configWatcher = watcher
        start()
        watcher.start()
        syncLoginItem(fromMenu: false)

        // Letter keys map through the layout, so a layout switch moves them.
        // Delivered immediately: a background app would otherwise get it late.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately
        )
        // Accessibility can drop across a reboot, and then the keys just look dead.
        axTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkAccessibility() }
        }
    }

    // A config that fails to load leaves the running one in place, so a typo
    // mid-edit doesn't take the keys away.
    private func start() {
        let data: Data
        do {
            data = try Data(contentsOf: ConfigFile.url)
        } catch {
            Toasts.show(Notice("No config yet", "Copy config.example.json to the path below. Tessera loads it as soon as it's there.",
                               code: ConfigFile.url.path), seconds: 15)
            return
        }
        configWatcher?.noteContents(data)
        let config: Config
        do {
            config = try Config.decode(data)
        } catch {
            let kept = engine == nil ? "Fix it and save; Tessera reloads on its own." : "The last config that loaded is still running."
            Toasts.show(Notice("Config not loaded", kept, code: "\(error)", action: .openConfig), seconds: 15)
            return
        }
        engine?.stop()
        let engine = Engine(config: config, platform: platform, scheduler: scheduler)
        self.engine = engine
        warnedHotkeys = []
        bindHotkeys()
        log.info("started, profile \(engine.profile ?? "none", privacy: .public)")
    }

    @objc private func inputSourceChanged() { bindHotkeys() }

    private func bindHotkeys() {
        let problems = hotkeys.bindAll(engine?.bindings ?? [])
        let fresh = problems.filter { !warnedHotkeys.contains($0) }
        warnedHotkeys.formUnion(fresh)
        guard !fresh.isEmpty else { return }
        Toasts.show(Notice(fresh.count == 1 ? "A shortcut won't work" : "\(fresh.count) shortcuts won't work",
                           "Change them in your config, or in System Settings > Keyboard > Keyboard Shortcuts.",
                           code: fresh.joined(separator: "\n"), action: .openConfig), seconds: 15)
    }

    private func handle(_ command: Control.Command, _ payload: String) -> String {
        switch command {
        case .status:
            let lines = engine?.status ?? ["No config loaded"]
            return (lines + ["Accessibility \(AXIsProcessTrusted() ? "on" : "off")"]).joined(separator: "\n")
        case .cycle:
            engine?.cycle(Int(payload) ?? 1)
        case .push:
            engine?.pushToBar()
        }
        return ""
    }

    // Unset means on, as Hammerspoon was; the menu toggle records a choice.
    private static let loginPreference = "openAtLogin"

    // SMAppService registers the running bundle, and a build copy is deleted by
    // the next `make app`, so only an installed copy touches the login item.
    private var isInstalled: Bool {
        let dir = Bundle.main.bundleURL.standardizedFileURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").standardizedFileURL.path
        return dir == "/Applications" || dir == home
    }

    nonisolated private static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    // Brings the login item in line with the preference. Off the main thread:
    // register and unregister wait on the login-items daemon.
    private func syncLoginItem(fromMenu: Bool) {
        guard isInstalled else { return }
        let want = UserDefaults.standard.object(forKey: Self.loginPreference) as? Bool ?? true
        Task.detached {
            let service = SMAppService.mainApp
            var failure: String?
            do {
                if want && !Self.isOn(service.status) { try service.register() }
                if !want && Self.isOn(service.status) { try await service.unregister() }
            } catch {
                failure = error.localizedDescription
            }
            let pending = want && service.status == .requiresApproval
            await MainActor.run {
                if let failure { Toasts.show(Notice("Couldn't change Open at Login", failure)) }
                guard pending else { return }
                if fromMenu {
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    Toasts.show(Notice("Allow Tessera to open at login",
                                       "macOS is holding it in System Settings > General > Login Items."))
                }
            }
        }
    }

    @objc private func toggleOpenAtLogin() {
        // Pending approval counts as on, so a click while pending turns it off.
        UserDefaults.standard.set(!Self.isOn(SMAppService.mainApp.status), forKey: Self.loginPreference)
        syncLoginItem(fromMenu: true)
    }

    private func checkAccessibility() {
        let ok = AXIsProcessTrusted()
        statusItem.button?.image = StatusIcon.make(attention: !ok)
        if !ok && !axWarned {
            Toasts.show(Notice("Tessera has no Accessibility permission",
                               "Nothing moves until it's back. Turn it on, then quit and reopen Tessera.",
                               action: .openAccessibilitySettings), seconds: 20)
        }
        axWarned = !ok
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let trusted = AXIsProcessTrusted()
        statusItem.button?.image = StatusIcon.make(attention: !trusted)
        if !trusted { addAccessibilityWarning(to: menu) }

        let state = engine?.menuState
        if let engine, let state {
            let header = add(menu, bold(state.profileName ?? "No profile"), chord: state.profileChord, enabled: false)
            header.toolTip = "The active profile"
            if !state.screens.isEmpty {
                add(menu, small(state.screens.joined(separator: " and ")), enabled: false)
            }
            menu.addItem(.separator())

            if !state.apps.isEmpty {
                menu.addItem(.sectionHeader(title: "Switcher"))
                for (i, app) in state.apps.enumerated() {
                    let title = app.running ? plain(app.name) : withNote(app.name, "opens on switch")
                    let item = add(menu, title, action: #selector(switchApp(_:)), chord: app.chord, enabled: trusted)
                    item.state = app.showing ? .on : .off
                    item.representedObject = i
                }
                add(menu, plain(state.maximized ? "Restore" : "Fill the Screen"), action: #selector(toggleMaximize),
                    chord: state.maximizeChord, enabled: trusted)
                menu.addItem(.separator())
            }

            menu.addItem(.sectionHeader(title: "Profiles"))
            for p in state.profiles {
                let title = p.fits ? plain(p.name) : withNote(p.name, "needs another screen")
                let item = add(menu, title, action: #selector(applyProfile(_:)), chord: p.chord, enabled: trusted)
                item.state = p.active ? .on : .off
                item.representedObject = p.id
            }
            menu.addItem(.separator())
            if state.overlayOn {
                let hold = KeyNames.glyphs(engine.config.keys.switcher)
                add(menu, withNote("Show Key Overlay", "or hold \(hold)"), action: #selector(showOverlay), enabled: trusted)
            }
        } else {
            add(menu, bold("No config loaded"), enabled: false)
            menu.addItem(.separator())
        }

        let login = add(menu, plain("Open at Login"), action: #selector(toggleOpenAtLogin))
        if !isInstalled {
            login.attributedTitle = withNote("Open at Login", "install to ~/Applications first")
            login.isEnabled = false
        } else {
            switch SMAppService.mainApp.status {
            case .enabled: login.state = .on
            case .requiresApproval:
                login.attributedTitle = withNote("Open at Login", "allow in System Settings")
                login.state = .mixed
            default: login.state = .off
            }
        }
        add(menu, plain("Edit Config…"), action: #selector(openConfig), chord: .init(modifiers: [.cmd], key: ","))
        add(menu, plain("Reload Config"), action: #selector(reload), chord: .init(modifiers: [.cmd], key: "r"))
        menu.addItem(.separator())
        if let state, trusted {
            let overlay = state.overlayOn ? "key overlay on" : "key overlay off"
            let status = add(menu, small("Ready: Accessibility on, \(overlay)"), enabled: false)
            status.image = dot(.systemGreen)
        }
        let quit = add(menu, plain("Quit Tessera"), chord: .init(modifiers: [.cmd], key: "q"))
        quit.action = #selector(NSApplication.terminate(_:))
        quit.target = NSApp
    }

    private func addAccessibilityWarning(to menu: NSMenu) {
        let title = add(menu, bold("Accessibility is off"), enabled: false)
        title.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?
            .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
        add(menu, small("Nothing moves until it's back. After turning it on, quit and reopen Tessera."), enabled: false)
        add(menu, plain("Open System Settings…"), action: #selector(openAccessibilitySettings))
        menu.addItem(.separator())
    }

    // MARK: Menu building

    @discardableResult
    private func add(_ menu: NSMenu, _ title: NSAttributedString, action: Selector? = nil,
                     chord: Engine.MenuState.Chord? = nil, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title.string, action: action, keyEquivalent: "")
        item.attributedTitle = title
        item.target = self
        item.isEnabled = enabled
        if let chord, let key = Self.keyEquivalent(chord.key) {
            item.keyEquivalent = key
            var mask: NSEvent.ModifierFlags = []
            if chord.modifiers.contains(.ctrl) { mask.insert(.control) }
            if chord.modifiers.contains(.alt) { mask.insert(.option) }
            if chord.modifiers.contains(.shift) { mask.insert(.shift) }
            if chord.modifiers.contains(.cmd) { mask.insert(.command) }
            item.keyEquivalentModifierMask = mask
        }
        menu.addItem(item)
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { Hotkeys.paused = true }
    func menuDidClose(_ menu: NSMenu) { Hotkeys.paused = false }

    // The character a menu item needs for a config key name; nil leaves the
    // shortcut off the item rather than showing a wrong one.
    private static func keyEquivalent(_ key: String) -> String? {
        let k = key.lowercased()
        if k.count == 1 { return k }
        let named: [String: String] = ["space": " ", "return": "\r", "tab": "\t", "escape": "\u{1b}", "delete": "\u{8}"]
        if let s = named[k] { return s }
        let function: [String: Int] = [
            "left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey,
            "up": NSUpArrowFunctionKey, "down": NSDownArrowFunctionKey,
        ]
        var code = function[k]
        if code == nil, k.hasPrefix("f"), let n = Int(k.dropFirst()), (1...12).contains(n) { code = NSF1FunctionKey + n - 1 }
        return code.flatMap { UnicodeScalar($0) }.map { String(Character($0)) }
    }

    private func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0)])
    }

    private func bold(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
    }

    private func small(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private func withNote(_ text: String, _ note: String) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: plain(text))
        out.append(NSAttributedString(string: "  ·  \(note)", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return out
    }

    private func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }

    @objc private func switchApp(_ sender: NSMenuItem) {
        guard let i = sender.representedObject as? Int else { return }
        engine?.switchTo(i)
    }

    @objc private func toggleMaximize() { engine?.toggleMaximize() }

    @objc private func showOverlay() { engine?.previewOverlay() }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        engine?.apply(profile: name)
    }

    @objc private func openConfig() { NSWorkspace.shared.open(ConfigFile.url) }

    @objc private func reload() { start() }
}

enum ConfigFile {
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["TESSERA_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/tessera/config.json")
    }

    static func load() throws -> Config {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw ConfigError("no config at \(url.path). Copy config.example.json there")
        }
        return try Config.decode(data)
    }
}
