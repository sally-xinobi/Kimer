import AppKit

/// Modal NSAlert that asks for a focus duration in minutes. Modal because the
/// app has no main window — a regular SwiftUI sheet has nothing to anchor to.
enum CustomTimerPrompt {

    private static let lastValueKey = "kimer.lastCustomMinutes"

    static func show(handler: @escaping (Int) -> Void) {
        // The character panels live at .statusBar; the alert needs to be
        // pinned above that or the user can't interact with it.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Custom Focus Timer"
        alert.informativeText = "How many minutes do you want to focus for? (1–600)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = .screenSaver

        let lastValue = UserDefaults.standard.integer(forKey: lastValueKey)
        let initial = lastValue > 0 ? lastValue : 30

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = String(initial)
        field.placeholderString = "minutes"
        field.alignment = .center
        alert.accessoryView = field

        // Make sure the field has focus and its content is selected so a single
        // keystroke can replace the prefilled value.
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let raw = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let mins = Int(raw), mins > 0 else { return }
        let clamped = max(1, min(mins, 600))
        UserDefaults.standard.set(clamped, forKey: lastValueKey)
        handler(clamped)
    }
}
