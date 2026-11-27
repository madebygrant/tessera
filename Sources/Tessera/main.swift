import AppKit
import TesseraCore

if let command = CommandLine.arguments.dropFirst().first, CLI.commands.contains(command) {
    exit(CLI.run(Array(CommandLine.arguments.dropFirst())))
}

// Renders sample overlays to PNGs, for checking the drawing without a live screen.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-overlay"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let size = CGSize(width: 1440, height: 900)
    let full = CGRect(origin: .zero, size: size)
    let left = CGRect(x: 0, y: 28, width: 720, height: 872)
    let right = CGRect(x: 720, y: 28, width: 720, height: 872)
    let samples: [String: [OverlayElement]] = [
        "switcher.png": [
            .scrim(full), .anchor(left, name: "Helium Dev"),
            .appList(right, rows: [
                .init(keys: ["⌃⌥", "1"], name: "Herdr", state: .showing),
                .init(keys: ["⌃⌥", "2"], name: "Zed", state: .ready),
                .init(keys: ["⌃⌥", "3"], name: "Obsidian", state: .notRunning),
            ], cycleKeys: ["⌃⌥", "←", "→"], maximizeKeys: ["⌃⌥", "F"], maximized: false),
            .profiles(full, chips: [
                .init(key: "H", name: "Offgrid", active: false), .init(key: "J", name: "Netrunner", active: true),
                .init(key: "K", name: "Cyberdeck", active: false), .init(key: "L", name: "Hardline", active: false),
            ], sharedModifiers: "⌃⌥⌘"),
        ],
        "slotmove.png": [
            .scrim(full), .slot(left, key: "1", name: "Left Half"), .slot(right, key: "2", name: "Right Half"),
            .focused(CGRect(x: 860, y: 120, width: 440, height: 290), app: "Finder"),
            .slotHint(full, modifiers: "⌃⌥⇧", app: "Finder"),
        ],
    ]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, elements) in samples {
        if let png = OverlayWindows.snapshot(elements, size: size) { try? png.write(to: dir.appending(path: name)) }
    }
    exit(0)
}

// `Tessera --check` validates the config and prints where each slot lands,
// without touching any window.
if CommandLine.arguments.contains("--check") {
    _ = NSApplication.shared
    do {
        ProfileImport.run()
        let config = try ConfigFile.load()
        let screens = MacPlatform().screens
        print("config ok: \(ConfigFile.url.path)")
        print("screens: \(screens.map(\.name).joined(separator: ", "))")
        for name in config.slots.keys.sorted() {
            let f = config.frame(ofSlot: name, screens: screens)
            print("  \(name): x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))")
        }
        print("keyboard layout: \(KeyLayout.name)")
        var clashes = 0
        for h in config.hotkeys {
            guard let code = KeyLayout.code(h.key), let mods = try? KeyNames.modifiers(h.modifiers) else { continue }
            let combo = KeyNames.glyphs(h.modifiers) + KeyNames.label(h.key)
            if code != KeyNames.code(h.key) { print("  \(combo) (\(h.purpose)) is key code \(code) on this layout") }
            if let system = SystemShortcuts.clash(code: code, modifiers: mods) {
                print("  \(combo) (\(h.purpose)) clashes with macOS: \(system)")
                clashes += 1
            }
        }
        print("\(config.hotkeys.count) hotkeys, \(clashes) clashing with macOS shortcuts")
        let saved = UserDefaults.standard.string(forKey: Engine.profileKey(screens.map(\.name)))
        print("profile at start: \(config.bestProfile(saved: saved, connected: screens.map(\.name)))")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Tessera: \(error)\n".utf8))
        exit(1)
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
