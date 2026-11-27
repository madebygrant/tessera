import CoreGraphics
import Testing
@testable import TesseraCore

@MainActor
struct OverlayTests {
    private let switcherMods: Set<Modifier> = [.ctrl, .alt]
    private let slotMods: Set<Modifier> = [.ctrl, .alt, .shift]

    private func scene(slotMove: Bool = true) throws -> (Scene, Engine) {
        var s = Scene()
        s.extra = #""overlay": { "delay": 1.0 },"# + (slotMove ? #""slotMove": {},"# : "")
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        return (s, try s.start())
    }

    // What the user's fingers do: the live state and the tap's event.
    private func hold(_ s: Scene, _ engine: Engine, _ mods: Set<Modifier>) {
        s.platform.heldModifiers = mods
        engine.handle(.modifiersChanged(mods))
    }

    // The overlay minus its scrims, which every layer draws per screen.
    private func shown(_ s: Scene) throws -> [OverlayElement] {
        try #require(s.platform.overlay).filter { if case .scrim = $0 { false } else { true } }
    }

    private func rows(_ elements: [OverlayElement]) -> [OverlayElement.AppRow] {
        for e in elements { if case let .appList(_, rows, _, _, _) = e { return rows } }
        return []
    }

    @Test func noBlockMeansNoKeyTap() throws {
        let s = Scene()
        let engine = try s.start()
        hold(s, engine, switcherMods)
        s.clock.advance(2)
        #expect(!s.platform.watchingKeys)
        #expect(s.platform.overlay == nil)
    }

    @Test func holdingShowsAfterTheDelayAndReleaseHides() throws {
        let (s, engine) = try scene()
        #expect(s.platform.watchingKeys)
        hold(s, engine, switcherMods)
        s.clock.advance(0.9)
        #expect(s.platform.overlay == nil)
        s.clock.advance(0.2)
        #expect(s.platform.overlay != nil)
        hold(s, engine, [])
        #expect(s.platform.overlay == nil)
    }

    @Test func aKeyBeforeTheDelayMakesItAChord() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(0.5)
        engine.handle(.keyDown)
        s.clock.advance(2)
        #expect(s.platform.overlay == nil)
    }

    @Test func otherModifierSetsShowNothing() throws {
        let (s, engine) = try scene()
        hold(s, engine, [.ctrl, .alt, .cmd])
        s.clock.advance(2)
        #expect(s.platform.overlay == nil)
    }

    @Test func switcherShowsAnchorAppListAndProfileStrip() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        let all = try #require(s.platform.overlay)
        #expect(all.first == .scrim(full))
        #expect(try shown(s) == [
            .anchor(left, name: "Zed"),
            .appList(right, rows: [
                .init(keys: ["⌃⌥", "1"], name: "Dev", state: .showing),
                .init(keys: ["⌃⌥", "2"], name: "Herdr", state: .notRunning),
            ], cycleKeys: ["⌃⌥", "←", "→"], maximizeKeys: ["⌃⌥", "F"], maximized: false),
            .profiles(full, chips: [
                .init(key: "H", name: "Offgrid", active: false),
                .init(key: "J", name: "Desk", active: true),
                .init(key: "T", name: "Twin", active: false),
            ], sharedModifiers: "⌃⌥⌘"),
        ])
    }

    @Test func aKeyWhileShowingRedrawsWithTheNewIndex() throws {
        let (s, engine) = try scene()
        s.platform.addWindow("Herdr")
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        engine.switcher.press(1)
        engine.handle(.keyDown)
        s.clock.advance(0.2)
        #expect(rows(try shown(s)).map(\.state) == [.ready, .showing])
    }

    @Test func sharedFrameSkipsTheAnchorBox() throws {
        let (s, engine) = try scene()
        s.clock.advance(3)
        engine.apply(profile: "offgrid")
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        let elements = try shown(s)
        #expect(!elements.contains { if case .anchor = $0 { true } else { false } })
        #expect(rows(elements).map(\.name) == ["Zed"])
    }

    @Test func slotMoveLayerShowsEachSlotInKeyOrderAndTheFocusedWindow() throws {
        let (s, engine) = try scene()
        let finder = s.platform.addWindow("Finder", frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        s.platform.bringToFront(finder)
        hold(s, engine, slotMods)
        s.clock.advance(1)
        #expect(try shown(s) == [
            .slot(right, key: "1", name: "Right"),
            .slot(full, key: "2", name: "Full"),
            .slot(left, key: "3", name: "Left"),
            .focused(CGRect(x: 100, y: 100, width: 400, height: 300), app: "Finder"),
            .slotHint(full, modifiers: "⌃⌥⇧", app: "Finder"),
        ])
    }

    @Test func slotMoveLayerNeedsSlotMoveOn() throws {
        let (s, engine) = try scene(slotMove: false)
        hold(s, engine, slotMods)
        s.clock.advance(2)
        #expect(s.platform.overlay == nil)
    }

    @Test func stoppingHidesItAndReleasesTheTap() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        engine.stop()
        #expect(s.platform.overlay == nil)
        #expect(!s.platform.watchingKeys)
    }

    @Test func aMissedReleaseNeverDraws() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        // Released while the tap was off: no event arrives.
        s.platform.heldModifiers = []
        s.clock.advance(2)
        #expect(s.platform.overlay == nil)
    }

    @Test func keyRepeatRedrawsOnceAfterTheLastKey() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        let before = s.platform.overlayDraws.count
        for _ in 0..<10 {
            engine.handle(.keyDown)
            s.clock.advance(0.03)
        }
        s.clock.advance(0.2)
        #expect(s.platform.overlayDraws.count == before + 1)
    }

    @Test func aRedrawDoesNotOutliveARelease() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        engine.handle(.keyDown)
        hold(s, engine, [])
        hold(s, engine, switcherMods)
        s.clock.advance(0.2)
        #expect(s.platform.overlay == nil)
    }

    @Test func aHotkeyCountsAsAChordEvenUnseenByTheTap() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(0.5)
        engine.bindings.first { $0.modifiers == ["ctrl", "alt"] && $0.key == "1" }!.action()
        s.clock.advance(2)
        #expect(s.platform.overlay == nil)
    }

    @Test func profileWithoutSwitcherAppsShowsNoKeyList() throws {
        let (s, engine) = try scene()
        s.clock.advance(3)
        engine.apply(profile: "twin")
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        #expect(rows(try shown(s)).isEmpty)
        #expect(try shown(s).first == .anchor(left, name: "Zed"))
    }

    @Test func previewShowsTheSwitcherWithoutKeysAndGoesAway() throws {
        let (s, engine) = try scene()
        engine.previewOverlay()
        #expect(!rows(try shown(s)).isEmpty)
        s.clock.advance(4.1)
        #expect(s.platform.overlay == nil)
    }

    @Test func prettyNamesSplitCamelCase() {
        #expect(prettyName("heliumDev") == "Helium Dev")
        #expect(prettyName("mainMax") == "Main Max")
        #expect(prettyName("zed") == "Zed")
    }

    @Test func negativeDelayIsAConfigError() {
        var s = Scene()
        s.extra = #""overlay": { "delay": -1 },"#
        #expect(throws: ConfigError("overlay.delay can't be negative")) { try s.config() }
    }
}
