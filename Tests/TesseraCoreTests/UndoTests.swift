import CoreGraphics
import Testing
@testable import TesseraCore

@MainActor
struct FlipTests {
    private func scene() throws -> (Scene, Engine) {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addWindow("Herdr")
        return (s, try s.start())
    }

    @Test func flipsBetweenTheLastTwoApps() throws {
        let (_, engine) = try scene()
        engine.switcher.press(1)
        engine.switcher.flip()
        #expect(engine.switcher.index == 0)
        engine.switcher.flip()
        #expect(engine.switcher.index == 1)
    }

    @Test func nothingToFlipToAtStart() throws {
        let (_, engine) = try scene()
        engine.switcher.flip()
        #expect(engine.switcher.index == 0)
    }

    @Test func repressingTheShownAppKeepsTheFlipTarget() throws {
        let (_, engine) = try scene()
        engine.switcher.press(1)
        engine.switcher.press(1)
        engine.switcher.flip()
        #expect(engine.switcher.index == 0)
    }

    @Test func aProfileSwitchForgetsTheFlipTarget() throws {
        let (_, engine) = try scene()
        engine.switcher.press(1)
        engine.layouts.apply("offgrid")
        engine.switcher.flip()
        #expect(engine.switcher.previous == nil)
    }

    @Test func keyIsBoundOnlyWhenSet() throws {
        var s = Scene()
        #expect(try s.start().bindings.allSatisfy { $0.purpose != "switcher previous" })
        s.edits = [(#""maximize": "f""#, #""maximize": "f", "previous": "tab", "undo": "z""#)]
        let bindings = try s.start().bindings
        #expect(bindings.contains { $0.purpose == "switcher previous" && $0.key == "tab" && $0.modifiers == ["ctrl", "alt"] })
        #expect(bindings.contains { $0.purpose == "undo" && $0.key == "z" })
    }

    @Test func unknownKeyNameIsRejected() {
        var s = Scene()
        s.edits = [(#""maximize": "f""#, #""maximize": "f", "undo": "zz""#)]
        #expect(throws: ConfigError.self) { try s.config() }
    }
}

@MainActor
struct UndoTests {
    @Test func undoPutsASlotMoveBackAndRedoes() throws {
        var s = Scene()
        s.extra = #""slotMove": {},"#
        let finderFrame = CGRect(x: 50, y: 60, width: 400, height: 300)
        let finder = s.platform.addWindow("Finder", frame: finderFrame)
        s.platform.bringToFront(finder)
        let engine = try s.start()
        engine.moveFocused(toSlot: 0)
        #expect(s.platform.frame(finder) == right)
        engine.undo()
        #expect(s.platform.frame(finder) == finderFrame)
        engine.undo()
        #expect(s.platform.frame(finder) == right)
    }

    @Test func undoRestoresTheProfileAndItsFrames() throws {
        let s = Scene()
        let zed = s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let ghostty = s.platform.addWindow("Ghostty")
        let engine = try s.start()
        let ghosttyBefore = s.platform.frame(ghostty)
        engine.layouts.apply("twin")
        #expect(engine.profile == "twin")
        engine.undo()
        #expect(engine.profile == "desk")
        #expect(s.platform.frame(ghostty) == ghosttyBefore)
        #expect(s.platform.frame(zed) == left)
    }

    @Test func reapplyingRightAfterUndoIsNotDebounced() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let ghostty = s.platform.addWindow("Ghostty")
        let engine = try s.start()
        engine.layouts.apply("twin")
        engine.undo()
        engine.layouts.apply("twin")
        #expect(engine.profile == "twin")
        #expect(s.platform.frame(ghostty) == left)
    }

    @Test func undoGoesBackToTheAppAndFocusFromBefore() throws {
        let s = Scene()
        let zed = s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addWindow("Herdr")
        let engine = try s.start()
        s.platform.bringToFront(zed)
        engine.switcher.press(1)
        engine.undo()
        #expect(engine.switcher.index == 0)
        #expect(s.platform.focusLog.last == zed)
    }

    @Test func nothingToUndoAtLoad() throws {
        let s = Scene()
        let zed = s.platform.addWindow("Zed", frame: CGRect(x: 5, y: 5, width: 300, height: 200))
        let engine = try s.start()
        engine.undo()
        #expect(s.platform.frame(zed) == left)
    }

    @Test func aScreenChangeClearsUndo() throws {
        var s = Scene()
        s.extra = #""slotMove": {},"#
        let finder = s.platform.addWindow("Finder", frame: CGRect(x: 50, y: 60, width: 400, height: 300))
        s.platform.bringToFront(finder)
        let engine = try s.start()
        engine.moveFocused(toSlot: 0)
        engine.handle(.screensChanged)
        engine.undo()
        #expect(s.platform.frame(finder) == right)
    }
}
