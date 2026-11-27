import CoreGraphics
import Foundation

public struct Insets: Codable, Sendable, Equatable {
    public var top: Double?
    public var left: Double?
    public var bottom: Double?
    public var right: Double?

    public init(top: Double? = nil, left: Double? = nil, bottom: Double? = nil, right: Double? = nil) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

// Fractions (0..1) of a screen's usable area, top-left origin.
public struct Slot: Codable, Sendable {
    public var screen: String
    public var x: Double?
    public var y: Double?
    public var w: Double?
    public var h: Double?

    public init(screen: String, x: Double? = nil, y: Double? = nil, w: Double? = nil, h: Double? = nil) {
        self.screen = screen
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct AppEntry: Codable, Sendable, Equatable {
    // App name as macOS reports it, or a bundle id.
    public var app: String
    public var titleSuffix: String?
    public var profileDir: String?
    public var launch: String?

    public init(app: String, titleSuffix: String? = nil, profileDir: String? = nil, launch: String? = nil) {
        self.app = app
        self.titleSuffix = titleSuffix
        self.profileDir = profileDir
        self.launch = launch
    }

    // Built the same way by the switcher and the profile applier, so the
    // window registry lines up between them.
    public var key: String { app + "\0" + (titleSuffix ?? "") }
}

public struct Keys: Codable, Sendable {
    public var switcher: [String]
    public var slotMove: [String]?
    public var profile: [String]?
    public var maximize: String
}

public struct SwitcherBlock: Codable, Sendable {
    public var anchor: String
    public var anchorSlot: String
    public var otherSlot: String
    public var fullSlot: String
    public var apps: [String]
    public var start: String?

    public var startIndex: Int {
        guard let start else { return 0 }
        return apps.firstIndex(of: start) ?? 0
    }
}

public struct Placement: Codable, Sendable {
    public var app: String
    public var slot: String
    public var useSwitcherWindow: Bool?
}

public struct Profile: Codable, Sendable {
    public var key: String
    public var modifier: [String]?
    public var screens: [String]?
    public var switcher: SwitcherBlock
    public var slots: [String]?
    public var place: [Placement]?

    // Slot-move key order: `slots` if given, else the slots `place` uses in
    // order of first appearance, which is how someone reads the profile.
    public var slotOrder: [String] {
        if let slots, !slots.isEmpty { return slots }
        var seen: Set<String> = []
        return (place ?? []).map(\.slot).filter { seen.insert($0).inserted }
    }
}

// An optional feature: off without its block, and `enabled: false` turns it
// off without deleting it.
public protocol FeatureBlock {
    var enabled: Bool? { get }
}

public struct Feature: Codable, Sendable, FeatureBlock {
    public var enabled: Bool?
}

public struct OverlayBlock: Codable, Sendable, FeatureBlock {
    public var enabled: Bool?
    // Long enough not to pop up while picking a number.
    public var delay: Double?
}

public struct Config: Codable, Sendable {
    public var screens: [String: String]
    public var screenInsets: [String: Insets]?
    public var gap: Double?
    public var slots: [String: Slot]
    public var apps: [String: AppEntry]
    public var keys: Keys
    public var profiles: [String: Profile]
    public var defaultProfile: String
    public var launchAtLoad: Bool?
    public var slotMove: Feature?
    public var overlay: OverlayBlock?

    public func isOn(_ feature: (some FeatureBlock)?) -> Bool {
        feature.map { $0.enabled != false } ?? false
    }

    public static func decode(_ data: Data) throws -> Config {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let config: Config
        do {
            config = try decoder.decode(Config.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError(describe(error))
        }
        try config.validate()
        return config
    }

    // Untitled entries skip windows whose title a titled sibling claims.
    public func reservedSuffixes(_ appName: String) -> [String] {
        apps.values.compactMap { $0.app == appName ? $0.titleSuffix : nil }
    }

    // `connected` is the localized names of the screens attached now.
    public func profileFits(_ name: String, connected: [String]) -> Bool {
        (profiles[name]?.screens ?? []).allSatisfy { ref in
            guard let spec = screens[ref] else { return false }
            return connected.contains { $0.contains(spec) }
        }
    }

    // A fitting `saved` wins: it was a choice. Otherwise the fitting profiles
    // needing the most screens, so a docked layout beats the laptop one.
    public func bestProfile(saved: String?, current: String? = nil, connected: [String]) -> String {
        if let saved, profiles[saved] != nil, profileFits(saved, connected: connected) { return saved }
        var most = -1
        var fitting: Set<String> = []
        for (name, p) in profiles where profileFits(name, connected: connected) {
            let n = p.screens?.count ?? 0
            if n > most { most = n; fitting = [] }
            if n == most { fitting.insert(name) }
        }
        if let current, fitting.contains(current) { return current }
        if fitting.contains(defaultProfile) { return defaultProfile }
        return fitting.sorted().first ?? defaultProfile
    }

    // Widest switcher list across profiles: that many number keys get bound.
    public var maxSwitcherApps: Int {
        profiles.values.map(\.switcher.apps.count).max() ?? 0
    }

    public var maxSlotMoveKeys: Int {
        profiles.values.map(\.slotOrder.count).max() ?? 0
    }
}

// Top-left origin, as AX uses. `inset` clears overlays macOS doesn't report
// (Sketchybar); `gap` comes off each edge, so neighbours sit 2*gap apart.
public func frameFor(screen f: CGRect, inset: Insets?, gap: Double, slot: Slot) -> CGRect {
    let i = inset ?? Insets()
    let x0 = f.minX + (i.left ?? 0)
    let y0 = f.minY + (i.top ?? 0)
    let w0 = f.width - (i.left ?? 0) - (i.right ?? 0)
    let h0 = f.height - (i.top ?? 0) - (i.bottom ?? 0)
    return CGRect(
        x: x0 + w0 * (slot.x ?? 0) + gap,
        y: y0 + h0 * (slot.y ?? 0) + gap,
        width: w0 * (slot.w ?? 1) - 2 * gap,
        height: h0 * (slot.h ?? 1) - 2 * gap
    )
}

public func centre(of r: CGRect, isIn frame: CGRect) -> Bool {
    let c = CGPoint(x: r.midX, y: r.midY)
    return c.x >= frame.minX && c.x <= frame.maxX && c.y >= frame.minY && c.y <= frame.maxY
}

public struct ConfigError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

private func describe(_ error: DecodingError) -> String {
    func path(_ ctx: DecodingError.Context) -> String {
        let p = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return p.isEmpty ? "the top level" : String(p.dropFirst())
    }
    switch error {
    case let .keyNotFound(key, ctx):
        let at = ctx.codingPath.isEmpty ? "" : " in \(path(ctx))"
        return "missing `\(key.stringValue)`\(at)"
    case let .typeMismatch(type, ctx), let .valueNotFound(type, ctx):
        return "\(path(ctx)) should be \(type)"
    case let .dataCorrupted(ctx):
        let underlying = (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
        return underlying ?? ctx.debugDescription
    @unknown default:
        return "\(error)"
    }
}
