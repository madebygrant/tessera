import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

private func config(_ profiles: String, default def: String = "desk", extra: String = "") throws -> Config {
    let json = """
    {
      "screens": { "main": "Built-in", "external": "LF32" },
      "slots": {
        "left": { "screen": "external", "x": 0, "w": 0.5 },
        "max": { "screen": "main" },
      },
      "apps": {
        "zed": { "app": "Zed" },
        "dev": { "app": "Helium", "titleSuffix": "Development" },
        "work": { "app": "Helium", "titleSuffix": "Work" },
        "plain": { "app": "Helium" },
      },
      "keys": { "switcher": ["ctrl", "alt"], "profile": ["ctrl", "alt", "cmd"], "maximize": "f" },
      "profiles": { \(profiles) },
      "defaultProfile": "\(def)",
      \(extra)
    }
    """
    return try Config.decode(Data(json.utf8))
}

private let sw = #""switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "left", "fullSlot": "max", "apps": ["dev", "zed"] }"#

private let threeProfiles = """
"desk": { "key": "j", "screens": ["external"], \(sw) },
"desk2": { "key": "k", "screens": ["external"], \(sw) },
"laptop": { "key": "h", \(sw) },
"""

@Test func bestProfilePrefersSavedWhenItFits() throws {
    let c = try config(threeProfiles)
    #expect(c.bestProfile(saved: "desk2", connected: ["Built-in Retina", "LF32TU87"]) == "desk2")
}

@Test func bestProfileIgnoresSavedThatDoesNotFit() throws {
    let c = try config(threeProfiles)
    #expect(c.bestProfile(saved: "desk2", connected: ["Built-in Retina"]) == "laptop")
}

@Test func bestProfilePrefersMostScreensThenCurrentThenDefault() throws {
    let c = try config(threeProfiles)
    let docked = ["Built-in Retina", "LF32TU87"]
    #expect(c.bestProfile(saved: nil, connected: docked) == "desk")
    #expect(c.bestProfile(saved: nil, current: "desk2", connected: docked) == "desk2")
    #expect(c.bestProfile(saved: nil, current: "laptop", connected: docked) == "desk")
}

@Test func frameAppliesInsetAndGap() {
    let slot = Slot(screen: "external", x: 0.5, y: 0, w: 0.5, h: 1)
    let f = frameFor(screen: CGRect(x: -2000, y: -500, width: 2000, height: 1028),
                     inset: Insets(top: 28), gap: 4, slot: slot)
    #expect(f == CGRect(x: -996, y: -468, width: 992, height: 992))
}

@Test func reservedSuffixesListTitledSiblings() throws {
    let c = try config(threeProfiles)
    #expect(Set(c.reservedSuffixes("Helium")) == ["Development", "Work"])
    #expect(c.reservedSuffixes("Zed").isEmpty)
}

@Test func startIndexFollowsStart() throws {
    let block = #""switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "left", "fullSlot": "max", "apps": ["dev", "zed"], "start": "zed" }"#
    let c = try config(#""desk": { "key": "j", \#(block) }"#)
    #expect(c.profiles["desk"]?.switcher.startIndex == 1)
}

@Test(arguments: [
    (#""desk": { "key": "j", "switcher": { "anchor": "nope", "anchorSlot": "left", "otherSlot": "left", "fullSlot": "max", "apps": [] } }"#,
     "profile 'desk' switcher.anchor names unknown app 'nope'"),
    (#""desk": { "key": "j", "switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "left", "fullSlot": "max", "apps": ["zed"], "start": "dev" } }"#,
     "profile 'desk' starts on 'dev', which is not in its switcher apps"),
    (#""desk": { "key": "ü", "switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "left", "fullSlot": "max", "apps": [] } }"#,
     "profile 'desk' key 'ü' is not a key Tessera knows"),
    (#""desk": { "key": "j", "modifier": [], "switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "left", "fullSlot": "max", "apps": [] } }"#,
     "profile 'desk' modifier needs at least one modifier"),
])
func validationNamesTheProblem(profiles: String, message: String) {
    #expect(throws: ConfigError(message)) { try config(profiles) }
}

@Test func missingFieldIsReadable() {
    #expect(throws: ConfigError("missing `key` in profiles.desk")) {
        try config(#""desk": { \#(sw) }"#)
    }
}
