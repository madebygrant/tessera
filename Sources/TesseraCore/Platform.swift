import CoreGraphics
import Foundation

public struct WinID: Hashable, Sendable, CustomStringConvertible {
    public let pid: Int32
    public let id: UInt32
    public init(pid: Int32, id: UInt32) {
        self.pid = pid
        self.id = id
    }
    public var description: String { "#\(id)" }
}

public struct WindowInfo: Sendable, Equatable {
    public let ref: WinID
    public let title: String
    public let isStandard: Bool
    public let frame: CGRect
    public init(ref: WinID, title: String, isStandard: Bool, frame: CGRect) {
        self.ref = ref
        self.title = title
        self.isStandard = isStandard
        self.frame = frame
    }
}

public struct AppProcess: Sendable, Equatable {
    public let pid: Int32
    public let name: String?
    public let bundleID: String?
    public init(pid: Int32, name: String?, bundleID: String?) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
    }

    // Config entries hold a name or a bundle id.
    public func matches(_ app: String) -> Bool { name == app || bundleID == app }
}

// Frames in top-left coordinates, as AX and CoreGraphics use.
public struct ScreenInfo: Sendable {
    public let name: String
    public let frame: CGRect
    public let usable: CGRect
    public init(name: String, frame: CGRect, usable: CGRect) {
        self.name = name
        self.frame = frame
        self.usable = usable
    }
}

public enum PlatformEvent: Sendable {
    case appLaunched(AppProcess)
    case appActivated(AppProcess)
    // A window appeared or retitled: anything waiting on this app re-checks.
    case windowsChanged(AppProcess)
    case windowResized(WinID)
    case screensChanged
    // From the key tap, only while watchKeys is on.
    case modifiersChanged(Set<Modifier>)
    case keyDown
}

// Everything the engine needs from macOS, so tests can swap in a fake.
@MainActor
public protocol Platform: AnyObject {
    var screens: [ScreenInfo] { get }
    var isTrusted: Bool { get }

    func processes(named app: String) -> [AppProcess]
    func windows(pid: Int32) -> [WindowInfo]
    func mainWindow(pid: Int32) -> WindowInfo?
    func focusedWindow(pid: Int32) -> WindowInfo?
    // The window with keyboard focus, whichever app owns it.
    func frontmostWindow() -> WindowInfo?
    // Native full screen: the window owns its own Space and won't take a frame.
    func isFullScreen(_ ref: WinID) -> Bool
    func window(_ ref: WinID) -> WindowInfo?

    // Unminimizes first.
    func setFrame(_ ref: WinID, _ frame: CGRect)
    func setPosition(_ ref: WinID, _ point: CGPoint)
    func raise(_ ref: WinID)
    func focus(_ ref: WinID)

    // Neither may call into the app over Accessibility: they guard against hung apps.
    func hasWindowOnOtherSpace(_ app: String) -> Bool
    func hasWindow(pid: Int32, in frame: CGRect) -> Bool

    // False when the entry has no launch recipe of its own.
    func spawn(_ entry: AppEntry) -> Bool
    func open(_ app: String)
    func openNewWindow(pid: Int32)

    // Apps whose window events should reach the engine.
    func observe(apps: Set<String>)
    func watchResize(_ ref: WinID)

    func savedProfile(_ key: String) -> String?
    func saveProfile(_ name: String, _ key: String)
    func showAlert(_ message: String)

    // `sketchybar --trigger event KEY=value...`, without waiting. A missing
    // sketchybar is a no-op, so this is safe on a machine without the bar.
    func triggerBar(bin: String?, event: String, fields: [(String, String)])

    func watchKeys(_ on: Bool)
    // Read live, for when a modifier release was missed.
    var heldModifiers: Set<Modifier> { get }
    func showOverlay(_ boxes: [OverlayBox])
    func hideOverlay()
}

@MainActor
public final class Cancellable {
    private var onCancel: (() -> Void)?
    public init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    public func cancel() {
        onCancel?()
        onCancel = nil
    }
}

@MainActor
public protocol Scheduler: AnyObject {
    var now: Double { get }
    @discardableResult
    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> Cancellable
}

@MainActor
public final class MainScheduler: Scheduler {
    public init() {}
    public var now: Double { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    public func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
        return Cancellable { task.cancel() }
    }
}

extension Config {
    // A missing monitor falls back to the first screen instead of erroring.
    public func frame(ofSlot name: String, screens list: [ScreenInfo]) -> CGRect {
        guard let slot = slots[name] else { return .zero }
        let spec = screens[slot.screen] ?? slot.screen
        guard let screen = list.first(where: { $0.name.contains(spec) }) ?? list.first else { return .zero }
        return frameFor(screen: screen.usable, inset: screenInsets?[slot.screen], gap: gap ?? 0, slot: slot)
    }
}

extension Config {
    // The usable area of the screen a slot lands on, after the same fallback.
    public func usableScreen(ofSlot name: String, screens list: [ScreenInfo]) -> CGRect? {
        guard let slot = slots[name] else { return nil }
        let spec = screens[slot.screen] ?? slot.screen
        return (list.first(where: { $0.name.contains(spec) }) ?? list.first)?.usable
    }
}

// The usable area of the screen holding most of `rect`.
public func usableFrame(containing rect: CGRect, screens: [ScreenInfo]) -> CGRect? {
    func area(_ s: ScreenInfo) -> CGFloat {
        let r = s.frame.intersection(rect)
        return r.isNull ? 0 : r.width * r.height
    }
    guard let best = screens.max(by: { area($0) < area($1) }), area(best) > 0 else { return nil }
    return best.usable
}
