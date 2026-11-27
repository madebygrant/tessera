import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

@MainActor
struct SlotMoveTests {
    private let slotMods = ["ctrl", "alt", "shift"]

    private func slotBindings(_ engine: Engine) -> [Binding] {
        engine.bindings.filter { $0.modifiers == slotMods }
    }

    private func press(_ engine: Engine, _ key: String) {
        slotBindings(engine).first { $0.key == key }!.action()
    }

    // An app Tessera has no entry for, focused.
    private func sceneWithFinder() throws -> (Scene, Engine, WinID) {
        var s = Scene()
        s.extra = #""slotMove": {},"#
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let finder = s.platform.addWindow("Finder")
        s.platform.bringToFront(finder)
        return (s, try s.start(), finder)
    }

    @Test func orderFollowsTheSlotsList() throws {
        let config = try Scene().config()
        #expect(config.profiles["twin"]?.slotOrder == ["right", "left", "full"])
    }

    @Test func orderFallsBackToPlaceInFirstAppearance() throws {
        let config = try Scene().config()
        #expect(config.profiles["desk"]?.slotOrder == ["right", "full", "left"])
    }

    @Test func noBlockBindsNoKeys() throws {
        let engine = try Scene().start()
        #expect(slotBindings(engine).isEmpty)
    }

    @Test func disabledBlockBindsNoKeys() throws {
        var s = Scene()
        s.extra = #""slotMove": { "enabled": false },"#
        #expect(slotBindings(try s.start()).isEmpty)
    }

    @Test func bindsTheLongestListAcrossProfiles() throws {
        let (_, engine, _) = try sceneWithFinder()
        #expect(slotBindings(engine).map(\.key) == ["1", "2", "3"])
    }

    @Test func movesTheFocusedWindowOfAnyApp() throws {
        let (s, engine, finder) = try sceneWithFinder()
        press(engine, "2")
        #expect(s.platform.frame(finder) == full)
    }

    @Test func followsTheActiveProfile() throws {
        let (s, engine, finder) = try sceneWithFinder()
        s.clock.advance(3)
        engine.apply(profile: "twin")
        press(engine, "1")
        #expect(s.platform.frame(finder) == right)
    }

    @Test func keyPastTheProfilesCountDoesNothing() throws {
        let (s, engine, finder) = try sceneWithFinder()
        let before = s.platform.frame(finder)
        s.clock.advance(3)
        engine.apply(profile: "offgrid")
        press(engine, "3")
        #expect(s.platform.frame(finder) == before)
    }

    @Test func leavesSheetsAndPalettesAlone() throws {
        let (s, engine, _) = try sceneWithFinder()
        let sheet = s.platform.addWindow("Finder", standard: false)
        s.platform.bringToFront(sheet)
        let before = s.platform.frame(sheet)
        press(engine, "1")
        #expect(s.platform.frame(sheet) == before)
    }

    @Test func leavesFullScreenWindowsAlone() throws {
        let (s, engine, finder) = try sceneWithFinder()
        s.platform.fullScreen.insert(finder)
        let before = s.platform.frame(finder)
        press(engine, "1")
        #expect(s.platform.frame(finder) == before)
    }

    @Test func movesTheFocusedWindowNotJustAnyOfTheApp() throws {
        let (s, engine, finder) = try sceneWithFinder()
        let other = s.platform.addWindow("Finder")
        s.platform.bringToFront(other)
        let before = s.platform.frame(finder)
        press(engine, "1")
        #expect(s.platform.frame(other) == right)
        #expect(s.platform.frame(finder) == before)
    }

    @Test func emptySlotsListFallsBackToPlace() throws {
        let json = sceneJSON.replacingOccurrences(of: #""slots": ["right", "left", "full"],"#, with: #""slots": [],"#)
            .replacingOccurrences(of: "EXTRA", with: "")
        let config = try Config.decode(Data(json.utf8))
        #expect(config.profiles["twin"]?.slotOrder == ["left", "right"])
    }

    @Test func duplicateSlotIsAConfigError() {
        let json = sceneJSON.replacingOccurrences(of: #""slots": ["right", "left", "full"],"#, with: #""slots": ["left", "left"],"#)
            .replacingOccurrences(of: "EXTRA", with: "")
        #expect(throws: ConfigError("profile 'twin' slots lists 'left' twice")) {
            try Config.decode(Data(json.utf8))
        }
    }

    @Test func clashWithTheSwitcherLayerIsAConfigError() {
        let json = sceneJSON
            .replacingOccurrences(of: #""slotMove": ["ctrl", "alt", "shift"]"#, with: #""slotMove": ["alt", "ctrl"]"#)
            .replacingOccurrences(of: "EXTRA", with: #""slotMove": {},"#)
        #expect(throws: ConfigError("ctrl+alt+1 is bound twice: switcher app 1 and slot move 1")) {
            try Config.decode(Data(json.utf8))
        }
    }

    @Test func clashWithAProfileKeyIsAConfigError() {
        let json = sceneJSON
            .replacingOccurrences(of: #""key": "h","#, with: #""key": "2", "modifier": ["shift", "ctrl", "alt"],"#)
            .replacingOccurrences(of: "EXTRA", with: #""slotMove": {},"#)
        #expect(throws: ConfigError("ctrl+alt+shift+2 is bound twice: profile 'offgrid' and slot move 2")) {
            try Config.decode(Data(json.utf8))
        }
    }

    @Test func onWithoutItsKeyLayerIsAConfigError() {
        let json = sceneJSON
            .replacingOccurrences(of: #""slotMove": ["ctrl", "alt", "shift"], "#, with: "")
            .replacingOccurrences(of: "EXTRA", with: #""slotMove": {},"#)
        #expect(throws: ConfigError("slotMove is on but keys.slotMove is missing")) {
            try Config.decode(Data(json.utf8))
        }
    }
}

@MainActor
struct HotkeyListTests {
    // The validator checks the config's list and the engine binds its own, so they must agree.
    @Test func engineBindsExactlyTheConfiguredHotkeys() throws {
        var s = Scene()
        s.extra = #""slotMove": {},"#
        let engine = try s.start()
        let bound = engine.bindings.map { "\($0.modifiers.joined(separator: "+"))+\($0.key)" }
        let listed = try s.config().hotkeys.map { "\($0.modifiers.joined(separator: "+"))+\($0.key)" }
        #expect(bound == listed)
    }
}

@MainActor
struct MenuStateTests {
    @Test func menuListsAppsAndProfilesWithTheirKeys() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let state = try s.start().menuState
        #expect(state.profileName == "Desk")
        #expect(state.profileChord?.key == "j")
        #expect(state.apps.map(\.name) == ["Dev", "Herdr"])
        #expect(state.apps.map(\.showing) == [true, false])
        #expect(state.apps.map(\.running) == [true, false])
        #expect(state.apps[1].chord?.modifiers == [.ctrl, .alt])
        #expect(state.apps[1].chord?.key == "2")
        #expect(state.profiles.map(\.name) == ["Offgrid", "Desk", "Twin"])
        #expect(state.profiles.map(\.active) == [false, true, false])
        #expect(state.profiles.filter { !$0.fits }.isEmpty)
    }

    @Test func profilesNeedingAMissingScreenAreMarked() throws {
        let s = Scene()
        s.platform.screens = [ScreenInfo(name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                         usable: CGRect(x: 0, y: 30, width: 1440, height: 870))]
        let state = try s.start().menuState
        #expect(state.profiles.filter { !$0.fits }.map(\.name) == ["Desk", "Twin"])
    }
}
