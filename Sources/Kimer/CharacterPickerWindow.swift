import AppKit
import SwiftUI

/// Holds a real titled NSWindow that hosts `CharacterPickerView`. Activates the
/// app so the picker is interactable (the rest of Kimer runs as `.accessory`),
/// then quits the app if the user closes the window without choosing — there's
/// nothing else for them to interact with at that point.
final class CharacterPickerWindowController {

    private var window: NSWindow?
    private var didSelect = false
    private var observer: NSObjectProtocol?

    func show(library: [CharacterAssets], onSelect: @escaping (String) -> Void) {
        let view = CharacterPickerView(library: library) { [weak self] id in
            self?.didSelect = true
            onSelect(id)
            self?.dismiss()
        }
        let host = NSHostingView(rootView: view)

        let initialSize = NSSize(width: 640, height: 280)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kimer"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // If the user closed the window without picking anything, the app
            // has no on-screen surface and no menu/dock affordance — quit so
            // we don't leave an invisible process behind.
            if !self.didSelect {
                NSApp.terminate(nil)
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func dismiss() {
        window?.close()
        window = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        // Drop the Dock icon again now that the picker is gone — Kimer is back
        // to its background-style identity.
        NSApp.setActivationPolicy(.accessory)
    }
}
