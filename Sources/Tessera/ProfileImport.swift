import Foundation

// Once: Hammerspoon's tessera saved the last profile per screen setup under its
// own defaults. Keys Tessera already has win.
enum ProfileImport {
    static func run() {
        let done = "importedHammerspoonProfiles"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: done),
              let old = UserDefaults(suiteName: "org.hammerspoon.Hammerspoon")?.dictionaryRepresentation()
        else { return }
        for (key, value) in old where key.hasPrefix("tessera.profile.") {
            let ours = String(key.dropFirst("tessera.".count))
            if defaults.object(forKey: ours) == nil, let name = value as? String { defaults.set(name, forKey: ours) }
        }
        defaults.set(true, forKey: done)
    }
}
