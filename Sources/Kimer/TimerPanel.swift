import AppKit

/// Floating, draggable, borderless panel that hosts the timer HUD. Lives at
/// the same window level as the character panels and only appears while a
/// session is running (or just completed, briefly, to flash the celebration).
final class TimerPanel: NSPanel {

    static let defaultsKey = "kimer.timerPanelOrigin"
    static let defaultSize = NSSize(width: 140, height: 56)

    var onMove: ((NSPoint) -> Void)?
    var onClick: (() -> Void)?

    init(initialFrame: NSRect) {
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = true
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var dragged = false
        let dragThreshold: CGFloat = 4

        eventLoop: while let next = nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            switch next.type {
            case .leftMouseUp:
                break eventLoop
            case .leftMouseDragged:
                let cur = NSEvent.mouseLocation
                let dx = cur.x - startMouse.x
                let dy = cur.y - startMouse.y
                if hypot(dx, dy) > dragThreshold { dragged = true }
                if dragged {
                    setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
                }
            default:
                break
            }
        }

        if dragged {
            onMove?(frame.origin)
        } else {
            onClick?()
        }
    }

    static func savedOrigin() -> NSPoint? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Double].self, from: data),
              decoded.count == 2
        else { return nil }
        return NSPoint(x: decoded[0], y: decoded[1])
    }

    static func saveOrigin(_ p: NSPoint) {
        let payload = [Double(p.x), Double(p.y)]
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let v = screen.visibleFrame
        let margin: CGFloat = 24
        // Top-right corner by default — sits above where most users park the
        // character panel without overlapping it.
        return NSPoint(
            x: v.maxX - defaultSize.width - margin,
            y: v.maxY - defaultSize.height - margin
        )
    }
}
