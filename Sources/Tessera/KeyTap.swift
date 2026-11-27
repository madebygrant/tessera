import AppKit
import TesseraCore

// Active, so it needs only Accessibility, not Input Monitoring. It holds each
// keystroke until the callback returns, so it runs on its own thread: on main,
// a slow AX call would stall typing everywhere.
final class KeyTap: @unchecked Sendable {
    var onEvent: ((PlatformEvent) -> Void)?

    // onEvent, watchdog and loggedFailure are main-thread only; the lock guards the rest.
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var watchdog: Timer?
    private var loggedFailure = false

    static func modifiers(_ flags: CGEventFlags) -> Set<Modifier> {
        var mods: Set<Modifier> = []
        if flags.contains(.maskControl) { mods.insert(.ctrl) }
        if flags.contains(.maskAlternate) { mods.insert(.alt) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskCommand) { mods.insert(.cmd) }
        return mods
    }

    static var held: Set<Modifier> { modifiers(CGEventSource.flagsState(.combinedSessionState)) }

    @MainActor
    func start() {
        guard watchdog == nil else { return }
        startThread()
        create()
        // macOS silently disables a tap it judges slow, and creation fails until
        // Accessibility is granted, so keep checking.
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.check() }
        }
    }

    @MainActor
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        lock.lock()
        defer { lock.unlock() }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source, let tapRunLoop { CFRunLoopRemoveSource(tapRunLoop, source, .commonModes) }
        tap = nil
        source = nil
    }

    // One thread for the app's lifetime, idling on a port when no tap is attached.
    private func startThread() {
        lock.lock()
        let running = tapRunLoop != nil
        lock.unlock()
        guard !running else { return }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            lock.lock()
            tapRunLoop = CFRunLoopGetCurrent()
            lock.unlock()
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "Tessera key tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    @MainActor
    private func create() {
        let mask = CGEventMask((1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue))
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon { Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let created else {
            if !loggedFailure { log.error("key tap unavailable; overlay off until Accessibility is granted") }
            loggedFailure = true
            return
        }
        loggedFailure = false
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, created, 0)
        lock.lock()
        tap = created
        source = runLoopSource
        if let tapRunLoop {
            CFRunLoopAddSource(tapRunLoop, runLoopSource, .commonModes)
            CFRunLoopWakeUp(tapRunLoop)
        }
        lock.unlock()
        CGEvent.tapEnable(tap: created, enable: true)
    }

    @MainActor
    private func check() {
        lock.lock()
        let current = tap
        lock.unlock()
        guard let current else { return create() }
        if !CGEvent.tapIsEnabled(tap: current) {
            CGEvent.tapEnable(tap: current, enable: true)
            resync()
        }
    }

    // Events while the tap was off are gone, a modifier release among them.
    private func resync() {
        let mods = Self.held
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onEvent?(.modifiersChanged(mods)) }
        }
    }

    // On the tap thread: read what's needed and hand it to main without waiting.
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        let emitted: PlatformEvent
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            lock.unlock()
            return resync()
        case .flagsChanged:
            emitted = .modifiersChanged(Self.modifiers(event.flags))
        case .keyDown:
            emitted = .keyDown
        default:
            return
        }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onEvent?(emitted) }
        }
    }
}
