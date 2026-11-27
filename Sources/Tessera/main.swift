import AppKit
import TesseraCore

// `Tessera --check` validates the config and prints where each slot lands,
// without touching any window.
if CommandLine.arguments.contains("--check") {
    _ = NSApplication.shared
    do {
        let config = try ConfigFile.load()
        let screens = MacPlatform().screens
        print("config ok: \(ConfigFile.url.path)")
        print("screens: \(screens.map(\.name).joined(separator: ", "))")
        for name in config.slots.keys.sorted() {
            let f = config.frame(ofSlot: name, screens: screens)
            print("  \(name): x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))")
        }
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
