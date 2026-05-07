import AppKit

/// Borderless panel that hosts the timer HUD. Auto-positioned by AppDelegate
/// directly underneath the primary character panel, so this panel itself is
/// not user-draggable — clicks toggle pause/resume but motion is suppressed.
final class TimerPanel: NSPanel {

    static let defaultSize = NSSize(width: 156, height: 44)

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
        isMovable = false
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
        // Click-only: we still wait for mouseUp so a press-drag-release doesn't
        // accidentally trigger pause, but we never move the panel — its origin
        // is owned by the character anchor logic in AppDelegate.
        let startMouse = NSEvent.mouseLocation
        var dragged = false
        let dragThreshold: CGFloat = 4

        eventLoop: while let next = nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            switch next.type {
            case .leftMouseUp:
                break eventLoop
            case .leftMouseDragged:
                let cur = NSEvent.mouseLocation
                if hypot(cur.x - startMouse.x, cur.y - startMouse.y) > dragThreshold {
                    dragged = true
                }
            default:
                break
            }
        }

        if !dragged {
            onClick?()
        }
    }
}
