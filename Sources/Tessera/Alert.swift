import AppKit
import os

let log = Logger(subsystem: "local.tessera", category: "app")

@MainActor
enum HUD {
    static func show(_ message: String, seconds: Double = 3) {
        log.error("\(message, privacy: .public)")
        let label = NSTextField(wrappingLabelWithString: "Tessera: " + message)
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.preferredMaxLayoutWidth = 560
        let size = label.fittingSize
        let pad: CGFloat = 18
        let rect = NSRect(x: 0, y: 0, width: size.width + pad * 2, height: size.height + pad * 2)

        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isReleasedWhenClosed = false

        let box = NSView(frame: rect)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        box.layer?.cornerRadius = 12
        label.frame = rect.insetBy(dx: pad, dy: pad)
        box.addSubview(label)
        panel.contentView = box

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.midX - rect.width / 2, y: v.minY + v.height * 0.25))
        }
        panel.orderFrontRegardless()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }
            panel.close()
        }
    }
}
