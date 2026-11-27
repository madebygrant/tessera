import CoreGraphics
import Testing
@testable import TesseraCore

@MainActor
struct SwitcherTests {
    @Test func startPlacesAnchorAndFirstAppWithoutFocus() throws {
        let s = Scene()
        let zed = s.platform.addWindow("Zed")
        let dev = s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        #expect(engine.profile == "desk")
        #expect(s.platform.frame(zed) == left)
        #expect(s.platform.frame(dev) == right)
        #expect(s.platform.focusLog.isEmpty)
    }

    @Test func switchingFocusesTheNewApp() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let herdr = s.platform.addWindow("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        #expect(s.platform.frame(herdr) == right)
        #expect(s.platform.focusLog.last == herdr)
    }

    @Test func keyPastTheProfilesCountDoesNothing() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let engine = try s.start()
        engine.switcher.press(5)
        #expect(engine.switcher.index == 0)
    }

    @Test func launchLandsOnTheWindowEventWithoutWaiting() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        engine.switcher.press(1)
        #expect(s.platform.launches == ["open Herdr"])

        let herdr = s.platform.addWindow("Herdr")
        engine.handle(.windowsChanged(s.platform.process("Herdr")))
        #expect(s.platform.frame(herdr) == right)
        #expect(s.platform.focusLog.last == herdr)
    }

    @Test func launchFallsBackToPollingWithoutAnEvent() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        engine.switcher.press(1)
        let herdr = s.platform.addWindow("Herdr")
        s.clock.advance(0.9)
        #expect(s.platform.frame(herdr) != right)
        s.clock.advance(0.2)
        #expect(s.platform.frame(herdr) == right)
    }

    @Test func launchTimesOutWithOneAlert() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        engine.switcher.press(1)
        s.clock.advance(4.5)
        #expect(s.platform.alerts.isEmpty)
        s.clock.advance(10)
        #expect(s.platform.alerts == ["no window from Herdr after 5s"])
    }

    @Test func switchingAwayCancelsAPendingLaunch() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        engine.switcher.press(1)
        engine.switcher.press(0)

        let herdr = s.platform.addWindow("Herdr")
        engine.handle(.windowsChanged(s.platform.process("Herdr")))
        s.clock.advance(10)
        #expect(s.platform.frame(herdr) != right)
        #expect(s.platform.alerts.isEmpty)
    }

    @Test func titledEntryWaitsForItsTitle() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let engine = try s.start()
        #expect(s.platform.launches == ["spawn Helium"])

        // Helium opens the window before the profile name reaches the title.
        let dev = s.platform.addWindow("Helium", title: "New Tab")
        engine.handle(.windowsChanged(s.platform.process("Helium")))
        #expect(s.platform.frame(dev) != right)

        s.platform.retitle(dev, "New Tab - Development")
        engine.handle(.windowsChanged(s.platform.process("Helium")))
        #expect(s.platform.frame(dev) == right)
    }

    @Test func offSpaceWindowBlocksTheLaunch() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.offSpace.insert("Herdr")
        s.platform.addApp("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        #expect(s.platform.launches.isEmpty)
        #expect(s.platform.alerts == ["Herdr has a window on another Space; not opening another"])
    }

    @Test func noLaunchAtLoadWhenDisabled() throws {
        var s = Scene()
        s.launchAtLoad = false
        _ = try s.start()
        #expect(s.platform.launches.isEmpty)
    }

    @Test func anchorRelaunchAdoptsItsWindowWithoutLaunching() throws {
        var s = Scene()
        s.launchAtLoad = false
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()

        let p = s.platform.addApp("Zed")
        engine.handle(.appLaunched(p))
        let zed = s.platform.addWindow("Zed")
        engine.handle(.windowsChanged(p))
        #expect(s.platform.frame(zed) == left)
        #expect(s.platform.launches.isEmpty)
        #expect(s.platform.focusLog.isEmpty)
    }

    @Test func maximizeTogglesBetweenOtherAndFullSlot() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let dev = s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        engine.switcher.toggleMaximize()
        #expect(s.platform.frame(dev) == full)
        engine.switcher.toggleMaximize()
        #expect(s.platform.frame(dev) == right)
    }
}

@MainActor
struct RestoreSlotTests {
    // Herdr is current in the right slot; Helium's dev window sits behind it.
    private func scene() throws -> (Scene, Engine, herdr: WinID, work: WinID) {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let work = s.platform.addWindow("Helium", title: "y - Work", frame: CGRect(x: 0, y: 0, width: 900, height: 900))
        let herdr = s.platform.addWindow("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        return (s, engine, herdr, work)
    }

    @Test func activationRaisesTheSlotsWindowOverAnIntruder() throws {
        let (s, engine, herdr, work) = try scene()
        let helium = s.platform.process("Helium")
        s.platform.focused[helium.pid] = work
        engine.handle(.appActivated(helium))
        #expect(s.platform.raised.last == herdr)
    }

    @Test func activatingAWindowInTheSlotLeavesItOnTop() throws {
        let (s, engine, _, _) = try scene()
        let helium = s.platform.process("Helium")
        s.platform.focused[helium.pid] = s.platform.windows(pid: helium.pid).first!.ref
        engine.handle(.appActivated(helium))
        #expect(s.platform.raised.isEmpty)
    }
}

@MainActor
struct LayoutTests {
    @Test func profilePlacesTitledWindowsAndReusesTheSwitchersWindow() throws {
        let s = Scene()
        let zed = s.platform.addWindow("Zed")
        let dev = s.platform.addWindow("Helium", title: "x - Development")
        let work = s.platform.addWindow("Helium", title: "y - Work")
        let herdrA = s.platform.addWindow("Herdr")
        let herdrB = s.platform.addWindow("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        s.platform.setFrameDirectly(herdrB, .zero)

        s.clock.advance(3)
        engine.apply(profile: "desk")
        #expect(s.platform.frame(dev) == right)
        #expect(s.platform.frame(work) == full)
        #expect(s.platform.frame(zed) == left)
        #expect(s.platform.frame(herdrA) == right)
        #expect(s.platform.frame(herdrB) == .zero)
    }

    @Test func secondEntryForAnAppAsksForANewWindow() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let first = s.platform.addWindow("Ghostty")
        let engine = try s.start()
        engine.apply(profile: "twin")
        #expect(s.platform.frame(first) == left)
        #expect(s.platform.launches.last == "new Ghostty")

        let second = s.platform.addWindow("Ghostty")
        engine.handle(.windowsChanged(s.platform.process("Ghostty")))
        #expect(s.platform.frame(second) == right)
    }

    @Test func aSupersededApplyStopsWaiting() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addWindow("Helium", title: "y - Work")
        let engine = try s.start()
        s.clock.advance(3)
        engine.apply(profile: "desk")
        engine.apply(profile: "offgrid")

        let herdr = s.platform.addWindow("Herdr")
        engine.handle(.windowsChanged(s.platform.process("Herdr")))
        s.clock.advance(10)
        #expect(s.platform.frame(herdr) != right)
        #expect(s.platform.alerts.isEmpty)
        #expect(engine.profile == "offgrid")
    }

    @Test func repressingTheActiveProfileKeepsTheSwitcherIndex() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.addWindow("Helium", title: "y - Work")
        let herdr = s.platform.addWindow("Herdr")
        let engine = try s.start()
        engine.switcher.press(1)
        s.clock.advance(3)
        engine.apply(profile: "desk")
        #expect(engine.switcher.index == 1)
        #expect(s.platform.raised.last == herdr)
    }

    @Test func doubleTapIsDebounced() throws {
        let s = Scene()
        let zed = s.platform.addWindow("Zed")
        let engine = try s.start()
        engine.apply(profile: "offgrid")
        s.platform.setFrameDirectly(zed, .zero)
        s.clock.advance(1)
        engine.apply(profile: "offgrid")
        #expect(s.platform.frame(zed) == .zero)
        s.clock.advance(1.5)
        engine.apply(profile: "offgrid")
        #expect(s.platform.frame(zed) != .zero)
    }

    @Test func undockingAppliesTheBestProfileWithoutLaunching() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        let launched = s.platform.launches
        s.platform.screens = [
            ScreenInfo(name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                       usable: CGRect(x: 0, y: 30, width: 1440, height: 870)),
        ]
        engine.handle(.screensChanged)
        engine.handle(.screensChanged)
        s.clock.advance(1.1)
        #expect(engine.profile == "offgrid")
        #expect(s.platform.launches == launched)
    }

    @Test func profileIsRememberedPerScreenSetup() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let engine = try s.start()
        s.clock.advance(3)
        engine.apply(profile: "twin")
        engine.stop()
        let again = try s.start()
        #expect(again.profile == "twin")
    }
}

@MainActor
struct ClampTests {
    @Test func appSnappingWiderIsPulledBackFromTheRightEdge() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let dev = s.platform.addWindow("Helium", title: "x - Development")
        _ = try s.start()
        #expect(s.platform.frame(dev).maxX == 2000)

        s.platform.afterSetFrame = { _, f in CGRect(x: f.minX, y: f.minY, width: f.width + 24, height: f.height) }
        let engine = try s.start()
        engine.switcher.press(0)
        #expect(s.platform.frame(dev).maxX == 2000)
        #expect(s.platform.frame(dev).width == 1024)
    }

    @Test func lateResizeFromTheAppIsClampedOnItsEvent() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let dev = s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        s.platform.setFrameDirectly(dev, CGRect(x: 1000, y: 0, width: 1030, height: 1000))
        engine.handle(.windowResized(dev))
        #expect(s.platform.frame(dev).maxX == 2000)
    }

    @Test func resizeLongAfterPlacementIsLeftAlone() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        let dev = s.platform.addWindow("Helium", title: "x - Development")
        let engine = try s.start()
        s.clock.advance(2)
        let wide = CGRect(x: 1000, y: 0, width: 1030, height: 1000)
        s.platform.setFrameDirectly(dev, wide)
        engine.handle(.windowResized(dev))
        #expect(s.platform.frame(dev) == wide)
    }
}

@MainActor
struct AlertTests {
    @Test func sameAlertShowsOncePerFiveSeconds() throws {
        let s = Scene()
        s.platform.addWindow("Zed")
        s.platform.addWindow("Helium", title: "x - Development")
        s.platform.isTrusted = false
        let engine = try s.start()
        engine.switcher.press(1)
        engine.switcher.press(1)
        #expect(s.platform.alerts.count == 1)
        s.clock.advance(5)
        engine.switcher.press(1)
        #expect(s.platform.alerts.count == 2)
    }
}
