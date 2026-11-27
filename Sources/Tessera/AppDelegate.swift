import AppKit
import TesseraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let platform = MacPlatform()
    private let scheduler = MainScheduler()
    private let hotkeys = Hotkeys()
    private var engine: Engine?
    private var statusItem: NSStatusItem!
    private var axTimer: Timer?
    private var axWarned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tessera")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        platform.onEvent = { [weak self] in self?.engine?.handle($0) }
        // Prompts once; macOS remembers the grant per signing identity.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        start()
        // Accessibility can drop across a reboot, and then the keys just look dead.
        axTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkAccessibility() }
        }
    }

    private func start() {
        engine?.stop()
        engine = nil
        hotkeys.unbindAll()
        do {
            let engine = Engine(config: try ConfigFile.load(), platform: platform, scheduler: scheduler)
            for b in engine.bindings { hotkeys.bind(b.modifiers, b.key, b.action) }
            self.engine = engine
            log.info("started, profile \(engine.profile ?? "none", privacy: .public)")
        } catch {
            HUD.show("config: \(error)", seconds: 8)
        }
    }

    private func checkAccessibility() {
        let ok = AXIsProcessTrusted()
        if !ok && !axWarned { HUD.show("no Accessibility permission; nothing will move until it's back") }
        axWarned = !ok
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let engine {
            for line in engine.status {
                menu.addItem(withTitle: line, action: nil, keyEquivalent: "").isEnabled = false
            }
            menu.addItem(.separator())
            for name in engine.config.profiles.keys.sorted() {
                let item = menu.addItem(withTitle: name, action: #selector(applyProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                item.state = name == engine.profile ? .on : .off
            }
        } else {
            menu.addItem(withTitle: "No config loaded", action: nil, keyEquivalent: "").isEnabled = false
        }
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Accessibility permission is off", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Config", action: #selector(openConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reload), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
