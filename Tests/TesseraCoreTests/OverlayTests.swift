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

    private func texts(_ box: OverlayBox) -> [String] {
        box.lines.map { $0.map(\.text).joined() }
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

    @Test func switcherShowsAnchorAppListAndProfileLegend() throws {
        let (s, engine) = try scene()
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        let boxes = try #require(s.platform.overlay)
        #expect(boxes.count == 3)
        #expect(boxes[0].placement == .fill(left))
        #expect(texts(boxes[0]) == ["Zed", "anchor"])

        #expect(boxes[1].placement == .fill(right))
        #expect(boxes[1].highlight)
        #expect(texts(boxes[1]) == ["⌃⌥1    Dev", "⌃⌥2    Herdr", "", "⌃⌥← →  cycle      ⌃⌥F  maximize"])
        #expect(boxes[1].lines[0][1].tone == .accent)
        #expect(boxes[1].lines[1][1].tone == .normal)

        #expect(boxes[2].placement == .legend(full))
        #expect(texts(boxes[2]) == ["⌃⌥⌘H  Offgrid     ⌃⌥⌘J  Desk     ⌃⌥⌘T  Twin"])
        #expect(boxes[2].lines[0].first { $0.text == "Desk" }?.tone == .accent)
    }

    @Test func aKeyWhileShowingRedrawsWithTheNewIndex() throws {
        let (s, engine) = try scene()
        s.platform.addWindow("Herdr")
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        engine.switcher.press(1)
        engine.handle(.keyDown)
        s.clock.advance(0.2)
        let boxes = try #require(s.platform.overlay)
        #expect(boxes[1].lines[1][1].tone == .accent)
    }

    @Test func sharedFrameSkipsTheAnchorBox() throws {
        let (s, engine) = try scene()
        s.clock.advance(3)
        engine.apply(profile: "offgrid")
        hold(s, engine, switcherMods)
        s.clock.advance(1)
        let boxes = try #require(s.platform.overlay)
        #expect(boxes.count == 2)
        #expect(texts(boxes[0]).first == "⌃⌥1    Zed")
    }

    @Test func slotMoveLayerShowsEachSlotInKeyOrder() throws {
        let (s, engine) = try scene()
        hold(s, engine, slotMods)
        s.clock.advance(1)
        let boxes = try #require(s.platform.overlay)
        #expect(boxes.map(\.placement) == [.fill(right), .fill(full), .fill(left)])
        #expect(texts(boxes[0]) == ["⌃⌥⇧1", "Right", "send the focused window here"])
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
        let boxes = try #require(s.platform.overlay)
        #expect(boxes.map(\.placement) == [.fill(left), .legend(full)])
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
