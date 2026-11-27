import Testing
@testable import TesseraCore

@MainActor
struct BarTests {
    private func scene(_ block: String = #""sketchybar": { "event": "tessera_switcher" },"#) throws -> (Scene, Engine) {
        var s = Scene()
        s.extra = block
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addWindow("Herdr")
        return (s, try s.start())
    }

    @Test func noBlockSendsNothing() throws {
        let (s, engine) = try scene("")
        engine.switcher.press(1)
        engine.pushToBar()
        #expect(s.platform.barTriggers.isEmpty)
    }

    @Test func startupPushesTheStartingState() throws {
        let (s, _) = try scene()
        #expect(s.platform.barTriggers.last ==
            "tessera_switcher APP=dev INDEX=1 COUNT=2 PROFILE=desk MAXIMIZED=false APP_NAME=Helium ANCHOR_NAME=Zed FOCUSED=false")
    }

    @Test func aSwitchClaimsFocus() throws {
        let (s, engine) = try scene()
        engine.switcher.press(1)
        #expect(s.platform.barTriggers.last ==
            "tessera_switcher APP=herdr INDEX=2 COUNT=2 PROFILE=desk MAXIMIZED=false APP_NAME=Herdr ANCHOR_NAME=Zed FOCUSED=true")
    }

    @Test func maximizeIsReported() throws {
        let (s, engine) = try scene()
        engine.switcher.toggleMaximize()
        #expect(s.platform.barTriggers.last?.contains(" MAXIMIZED=true ") == true)
        #expect(s.platform.barTriggers.last?.hasSuffix("FOCUSED=true") == true)
    }

    @Test func aProfileChangeRetargetsWithoutClaimingFocus() throws {
        let (s, engine) = try scene()
        s.clock.advance(3)
        engine.apply(profile: "offgrid")
        #expect(s.platform.barTriggers.last ==
            "tessera_switcher APP=zed INDEX=1 COUNT=1 PROFILE=offgrid MAXIMIZED=false APP_NAME=Zed ANCHOR_NAME=Zed FOCUSED=false")
    }

    @Test func eventNameAndBinaryComeFromTheConfig() throws {
        let (s, _) = try scene(#""sketchybar": { "event": "custom_event", "bin": "/opt/bar" },"#)
        #expect(s.platform.barTriggers.last?.hasPrefix("custom_event ") == true)
        #expect(s.platform.barBins.last == "/opt/bar")
    }

    @Test func explicitPushRepeatsTheCurrentState() throws {
        let (s, engine) = try scene()
        engine.switcher.press(1)
        engine.pushToBar()
        #expect(s.platform.barTriggers.last?.contains("APP=herdr") == true)
        #expect(s.platform.barTriggers.last?.hasSuffix("FOCUSED=false") == true)
    }

    @Test func scrollCyclingIsThrottled() throws {
        let (s, engine) = try scene()
        engine.cycle(1)
        engine.cycle(1)
        #expect(engine.switcher.index == 1)
        s.clock.advance(0.4)
        engine.cycle(1)
        #expect(engine.switcher.index == 0)
    }

    @Test func bundleIDEntriesAreSentAsDisplayNames() throws {
        var s = Scene()
        s.extra = #""sketchybar": {},"#
        s.edits = [(#""herdr":   { "app": "Herdr" }"#, #""herdr":   { "app": "com.test.herdr" }"#)]
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addWindow("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        #expect(s.platform.barTriggers.last?.contains(" APP_NAME=Herdr ") == true)
    }

    @Test func aBlockedSwitchDoesNotClaimFocus() throws {
        var s = Scene()
        s.extra = #""sketchybar": {},"#
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addApp("Herdr")
        s.platform.offSpace.insert("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        #expect(s.platform.barTriggers.last?.hasSuffix("FOCUSED=false") == true)
    }

    @Test func aLaunchClaimsFocusWhenItsWindowLands() throws {
        var s = Scene()
        s.extra = #""sketchybar": {},"#
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        engine.switcher.press(1)
        #expect(s.platform.barTriggers.last?.hasSuffix("FOCUSED=false") == true)
        s.platform.addWindow("Herdr")
        engine.handle(.windowsChanged(s.platform.process("Herdr")))
        #expect(s.platform.barTriggers.last?.contains("APP_NAME=Herdr") == true)
        #expect(s.platform.barTriggers.last?.hasSuffix("FOCUSED=true") == true)
    }

    @Test func extremeStepsWrapInsteadOfTrapping() throws {
        let (s, engine) = try scene()
        engine.switcher.press(1)
        engine.switcher.step(Int.max)
        s.clock.advance(1)
        engine.cycle(Int.min)
        #expect((0..<2).contains(engine.switcher.index))
    }
}
