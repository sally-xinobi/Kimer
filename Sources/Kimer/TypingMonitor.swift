import AppKit
import IOKit.hid

/// Watches global key-down events and forwards them to a `TypingSpeedTracker`.
///
/// Uses `NSEvent.addGlobalMonitorForEvents` which on macOS 10.15+ requires the
/// "Input Monitoring" privacy permission. We probe / request it via the
/// IOHID access APIs and surface a manual-grant prompt if the user denied.
final class TypingMonitor {

    private weak var tracker: TypingSpeedTracker?
    private var monitor: Any?
    private var didShowAlert = false

    init(tracker: TypingSpeedTracker) {
        self.tracker = tracker
    }

    deinit {
        stop()
    }

    func start() {
        ensureInputMonitoringAccess()

        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.didReceiveKeystroke()
        }
        let installed = monitor != nil
        fputs("Kimer: global keyDown monitor installed=\(installed)\n", stderr)
    }

    private var loggedFirstKeystroke = false

    private func didReceiveKeystroke() {
        if !loggedFirstKeystroke {
            loggedFirstKeystroke = true
            fputs("Kimer: first keystroke received — Input Monitoring permission OK\n", stderr)
        }
        tracker?.recordKeystroke()
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    // MARK: - Permission

    private func ensureInputMonitoringAccess() {
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        fputs("Kimer: IOHIDCheckAccess(listenEvent) = \(describe(status))\n", stderr)
        if status == kIOHIDAccessTypeGranted { return }

        // Triggers the system prompt the first time the app is run with this
        // bundle id. After the user dismisses it, subsequent calls just return
        // the recorded decision without prompting again.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        fputs("Kimer: IOHIDRequestAccess returned granted=\(granted)\n", stderr)
        if !granted, !didShowAlert {
            didShowAlert = true
            showPermissionAlert()
        }
    }

    private func describe(_ s: IOHIDAccessType) -> String {
        switch s {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied:  return "denied"
        case kIOHIDAccessTypeUnknown: return "unknown (not yet decided)"
        default: return "raw=\(s.rawValue)"
        }
    }

    private func showPermissionAlert() {
        DispatchQueue.main.async {
            // The character panel sits at .statusBar level, so a default alert
            // window can be hidden behind it. Activate the app and pin the
            // alert window above .statusBar so the user actually sees it.
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Kimer needs Input Monitoring access"
            alert.informativeText = """
            Kimer listens for keystrokes globally so the character can react when you type.

            Open System Settings → Privacy & Security → Input Monitoring and enable Kimer, then relaunch the app.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")

            alert.window.level = .screenSaver

            let response = alert.runModal()
            if response == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
