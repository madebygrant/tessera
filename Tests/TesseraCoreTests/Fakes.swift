import CoreGraphics
import Foundation
@testable import TesseraCore

@MainActor
final class FakeClock: Scheduler {
    private struct Job {
        let at: Double
        let seq: Int
        let action: @MainActor () -> Void
    }

    private(set) var now = 0.0
    private var jobs: [Int: Job] = [:]
    private var seq = 0

    @discardableResult
    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        seq += 1
        let id = seq
        jobs[id] = Job(at: now + seconds, seq: id, action: action)
        return Cancellable { [weak self] in self?.jobs[id] = nil }
    }

    // Runs due jobs in time order, including ones they schedule.
    func advance(_ seconds: Double) {
        let end = now + seconds
        while let next = jobs.values.filter({ $0.at <= end + 1e-9 }).min(by: { ($0.at, $0.seq) < ($1.at, $1.seq) }) {
            jobs[next.seq] = nil
            now = max(now, next.at)
            next.action()
        }
        now = end
    }
}

@MainActor
final class FakePlatform: Platform {
    var screens = [
        ScreenInfo(name: "LF32TU87", frame: CGRect(x: 0, y: 0, width: 2000, height: 1000),
                   usable: CGRect(x: 0, y: 0, width: 2000, height: 1000)),
    ]
    var isTrusted = true

    private(set) var procs: [AppProcess] = []
    private var order: [WinID] = []
    private var wins: [WinID: WindowInfo] = [:]
    var main: [Int32: WinID] = [:]
    var focused: [Int32: WinID] = [:]
    var offSpace: Set<String> = []
    var saved: [String: String] = [:]

    private(set) var launches: [String] = []
    private(set) var focusLog: [WinID] = []
    private(set) var raised: [WinID] = []
    private(set) var alerts: [String] = []
    private(set) var observed: Set<String> = []
    // An app's own reaction to being sized, like Ghostty snapping wider.
    var afterSetFrame: ((WinID, CGRect) -> CGRect)?

    private var nextPid: Int32 = 100
    private var nextWin: UInt32 = 1

    @discardableResult
    func addApp(_ name: String, bundleID: String? = nil) -> AppProcess {
        if let p = procs.first(where: { $0.name == name }) { return p }
        let p = AppProcess(pid: nextPid, name: name, bundleID: bundleID ?? "com.test.\(name.lowercased())")
        nextPid += 1
        procs.append(p)
        return p
    }

    @discardableResult
    func addWindow(_ app: String, title: String = "", frame: CGRect = CGRect(x: 10, y: 10, width: 300, height: 200), standard: Bool = true) -> WinID {
        let p = addApp(app)
        let ref = WinID(pid: p.pid, id: nextWin)
        nextWin += 1
        order.append(ref)
        wins[ref] = WindowInfo(ref: ref, title: title, isStandard: standard, frame: frame)
        return ref
    }

    func process(_ app: String) -> AppProcess { procs.first { $0.name == app }! }
    func frame(_ ref: WinID) -> CGRect { wins[ref]!.frame }

    func setFrameDirectly(_ ref: WinID, _ frame: CGRect) {
        let w = wins[ref]!
        wins[ref] = WindowInfo(ref: ref, title: w.title, isStandard: w.isStandard, frame: frame)
    }

    func retitle(_ ref: WinID, _ title: String) {
        let w = wins[ref]!
        wins[ref] = WindowInfo(ref: ref, title: title, isStandard: w.isStandard, frame: w.frame)
    }

    // MARK: Platform

    func processes(named app: String) -> [AppProcess] { procs.filter { $0.matches(app) } }
    func windows(pid: Int32) -> [WindowInfo] { order.filter { $0.pid == pid }.compactMap { wins[$0] } }
    func mainWindow(pid: Int32) -> WindowInfo? { main[pid].flatMap { wins[$0] } }
    func focusedWindow(pid: Int32) -> WindowInfo? { focused[pid].flatMap { wins[$0] } }
    var frontmostPid: Int32?
    var fullScreen: Set<WinID> = []
    func frontmostWindow() -> WindowInfo? { frontmostPid.flatMap { focusedWindow(pid: $0) } }
    func isFullScreen(_ ref: WinID) -> Bool { fullScreen.contains(ref) }

    // The user clicked into this window.
    func bringToFront(_ ref: WinID) {
        frontmostPid = ref.pid
        focused[ref.pid] = ref
    }
    func window(_ ref: WinID) -> WindowInfo? { wins[ref] }

    func setFrame(_ ref: WinID, _ frame: CGRect) {
        setFrameDirectly(ref, afterSetFrame?(ref, frame) ?? frame)
    }

    func setPosition(_ ref: WinID, _ point: CGPoint) {
        setFrameDirectly(ref, CGRect(origin: point, size: frame(ref).size))
    }

    func raise(_ ref: WinID) { raised.append(ref) }
    func focus(_ ref: WinID) { focusLog.append(ref) }

    func hasWindowOnOtherSpace(_ app: String) -> Bool { offSpace.contains(app) }

    func hasWindow(pid: Int32, in frame: CGRect) -> Bool {
        windows(pid: pid).contains { centre(of: $0.frame, isIn: frame) }
    }

    func spawn(_ entry: AppEntry) -> Bool {
        guard entry.launch != nil || entry.profileDir != nil else { return false }
        launches.append("spawn \(entry.app)")
        return true
    }

    func open(_ app: String) { launches.append("open \(app)") }

    func openNewWindow(pid: Int32) {
        launches.append("new \(procs.first { $0.pid == pid }?.name ?? "?")")
    }

    func observe(apps: Set<String>) { observed = apps }
    func watchResize(_ ref: WinID) {}

    func savedProfile(_ key: String) -> String? { saved[key] }
    func saveProfile(_ name: String, _ key: String) { saved[key] = name }
    func showAlert(_ message: String) { alerts.append(message) }
}

// External 2000x1000: left and right halves, plus full. Laptop: max.
let sceneJSON = """
{
  "screens": { "external": "LF32", "main": "Built-in" },
  "slots": {
    "left":  { "screen": "external", "x": 0,   "w": 0.5 },
    "right": { "screen": "external", "x": 0.5, "w": 0.5 },
    "full":  { "screen": "external" },
    "max":   { "screen": "main" },
  },
  "apps": {
    "zed":     { "app": "Zed" },
    "herdr":   { "app": "Herdr" },
    "ghostty": { "app": "Ghostty" },
    "dev":     { "app": "Helium", "titleSuffix": "Development", "profileDir": "Default" },
    "work":    { "app": "Helium", "titleSuffix": "Work", "profileDir": "Profile 1" },
  },
  "keys": { "switcher": ["ctrl", "alt"], "profile": ["ctrl", "alt", "cmd"], "slotMove": ["ctrl", "alt", "shift"], "maximize": "f" },
  "profiles": {
    "desk": {
      "key": "j", "screens": ["external"],
      "switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "right", "fullSlot": "full", "apps": ["dev", "herdr"] },
      "place": [
        { "app": "dev",   "slot": "right" },
        { "app": "work",  "slot": "full" },
        { "app": "herdr", "slot": "right", "useSwitcherWindow": true },
        { "app": "zed",   "slot": "left" },
      ],
    },
    "twin": {
      "key": "t", "screens": ["external"],
      "switcher": { "anchor": "zed", "anchorSlot": "left", "otherSlot": "right", "fullSlot": "full", "apps": [] },
      "slots": ["right", "left", "full"],
      "place": [
        { "app": "ghostty", "slot": "left" },
        { "app": "ghostty", "slot": "right" },
      ],
    },
    "offgrid": {
      "key": "h",
      "switcher": { "anchor": "zed", "anchorSlot": "max", "otherSlot": "max", "fullSlot": "max", "apps": ["zed"] },
      "place": [{ "app": "zed", "slot": "max" }],
    },
  },
  "defaultProfile": "desk",
  EXTRA
}
"""

let left = CGRect(x: 0, y: 0, width: 1000, height: 1000)
let right = CGRect(x: 1000, y: 0, width: 1000, height: 1000)
let full = CGRect(x: 0, y: 0, width: 2000, height: 1000)

@MainActor
struct Scene {
    let platform = FakePlatform()
    let clock = FakeClock()
    var launchAtLoad = true
    // Extra top-level JSON5 members, such as feature blocks.
    var extra = ""

    func config() throws -> Config {
        let json = sceneJSON.replacingOccurrences(of: "EXTRA", with: (launchAtLoad ? "" : "\"launchAtLoad\": false,") + extra)
        return try Config.decode(Data(json.utf8))
    }

    func start() throws -> Engine {
        try Engine(config: config(), platform: platform, scheduler: clock)
    }
}
