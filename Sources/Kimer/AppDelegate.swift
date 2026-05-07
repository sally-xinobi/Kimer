import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var tracker: TypingSpeedTracker?
    private var monitor: TypingMonitor?
    private var store: InstancesStore?
    private var timerStore: StudyTimerStore?

    private var panels: [UUID: CharacterPanel] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var sizeCancellables: [UUID: AnyCancellable] = [:]

    private var timerPanel: TimerPanel?
    private var timerHostingView: NSHostingView<TimerHUDView>?
    private var timerHideWorkItem: DispatchWorkItem?

    private var pickerController: CharacterPickerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background-style app: no Dock icon, no menu bar item. (The picker
        // briefly flips to .regular while it's on screen and flips back to
        // .accessory once dismissed.)
        NSApp.setActivationPolicy(.accessory)

        let library = VideoLoader.loadLibrary()
        if library.isEmpty {
            fputs("Kimer: no <name>_idle.* / <name>_run.* video pairs found in Resources — placeholder will show.\n", stderr)
        }

        let tracker = TypingSpeedTracker()
        let store = InstancesStore(library: library)
        let timerStore = StudyTimerStore()
        self.tracker = tracker
        self.store = store
        self.timerStore = timerStore

        // Spawn one panel per instance, then keep them in sync as the store mutates.
        for inst in store.instances {
            spawnPanel(for: inst, tracker: tracker, store: store, timerStore: timerStore)
        }
        store.$instances
            .sink { [weak self] list in
                self?.syncPanels(with: list, tracker: tracker, store: store, timerStore: timerStore)
            }
            .store(in: &cancellables)

        // First-run experience: no saved instances → show the picker so the
        // user opts in to a starting companion instead of being silently
        // assigned mouse.
        if store.instances.isEmpty, !library.isEmpty {
            showCharacterPicker(library: library, store: store)
        }

        // Show / hide the timer HUD based on session state.
        timerStore.$session
            .removeDuplicates()
            .sink { [weak self] session in
                self?.handleTimerSessionChanged(session: session, timerStore: timerStore)
            }
            .store(in: &cancellables)

        timerStore.$lastCompletion
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.flashTimerHUDOnCompletion(timerStore: timerStore)
            }
            .store(in: &cancellables)

        timerStore.ensureNotificationAuthorization()

        let monitor = TypingMonitor(tracker: tracker)
        monitor.start()
        self.monitor = monitor
    }

    private func syncPanels(with instances: [CharacterInstance],
                            tracker: TypingSpeedTracker,
                            store: InstancesStore,
                            timerStore: StudyTimerStore) {
        let aliveIDs = Set(instances.map { $0.id })
        // remove panels whose instance is gone
        for id in Array(panels.keys) where !aliveIDs.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
            sizeCancellables.removeValue(forKey: id)
        }
        // spawn panels for newly added instances
        for inst in instances where panels[inst.id] == nil {
            spawnPanel(for: inst, tracker: tracker, store: store, timerStore: timerStore)
        }
    }

    private func spawnPanel(for instance: CharacterInstance,
                            tracker: TypingSpeedTracker,
                            store: InstancesStore,
                            timerStore: StudyTimerStore) {
        let frame = NSRect(origin: instance.origin, size: instance.size.nsSize)
        let panel = CharacterPanel(initialFrame: frame)

        let view = CharacterView(
            tracker: tracker,
            instance: instance,
            store: store,
            timerStore: timerStore
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: instance.size.nsSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.onClick = { [weak instance] in
            instance?.recordClick()
        }
        panel.onMove = { [weak self, weak instance] newOrigin in
            instance?.updateOrigin(newOrigin)
            self?.anchorTimerHUDIfVisible()
        }

        panel.orderFrontRegardless()
        panels[instance.id] = panel

        // Resize the panel whenever this instance's size changes.
        sizeCancellables[instance.id] = instance.$sizeRaw
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self, weak panel, weak instance] _ in
                guard let panel, let instance else { return }
                panel.applySize(instance.size.nsSize)
                self?.anchorTimerHUDIfVisible()
            }
    }

    // MARK: - Timer HUD

    private func handleTimerSessionChanged(session: StudySession?,
                                           timerStore: StudyTimerStore) {
        if session != nil {
            showTimerHUD(timerStore: timerStore)
            timerHideWorkItem?.cancel()
            timerHideWorkItem = nil
        } else if timerStore.lastCompletion == nil {
            // Session was stopped manually (no completion flash needed).
            hideTimerHUD()
        }
        // If lastCompletion is set, we leave the panel visible and let
        // flashTimerHUDOnCompletion schedule the dismissal.
    }

    private func flashTimerHUDOnCompletion(timerStore: StudyTimerStore) {
        showTimerHUD(timerStore: timerStore)
        timerHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideTimerHUD()
        }
        timerHideWorkItem = work
        // 6s lets the user notice the celebration without the chip lingering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func showTimerHUD(timerStore: StudyTimerStore) {
        if timerPanel == nil {
            let frame = NSRect(origin: anchoredTimerOrigin(), size: TimerPanel.defaultSize)
            let panel = TimerPanel(initialFrame: frame)
            let view = TimerHUDView(store: timerStore)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: TimerPanel.defaultSize)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.onClick = { [weak timerStore] in
                // Click toggles pause/resume when a session is active. When no
                // session, the click is a no-op — discovery happens via the
                // right-click menu.
                guard let timerStore, timerStore.session != nil else { return }
                timerStore.pauseOrResume()
            }
            timerPanel = panel
            timerHostingView = host
        } else {
            anchorTimerHUDIfVisible()
        }
        timerPanel?.orderFrontRegardless()
    }

    private func hideTimerHUD() {
        timerPanel?.orderOut(nil)
        timerPanel = nil
        timerHostingView = nil
    }

    /// Position the timer panel so it sits centered horizontally on the
    /// primary character and slightly below it. Called whenever the character
    /// moves or resizes.
    private func anchorTimerHUDIfVisible() {
        guard let timerPanel else { return }
        let origin = anchoredTimerOrigin()
        timerPanel.setFrameOrigin(origin)
    }

    private func anchoredTimerOrigin() -> NSPoint {
        let timerSize = TimerPanel.defaultSize
        let gap: CGFloat = 6

        // Anchor under the first instance — that's the "primary" companion.
        if let primary = store?.instances.first,
           let charPanel = panels[primary.id] {
            let charFrame = charPanel.frame
            let proposed = NSPoint(
                x: charFrame.midX - timerSize.width / 2,
                y: charFrame.minY - timerSize.height - gap
            )
            return clampToVisibleScreen(origin: proposed, size: timerSize)
        }

        // Fallback when no character is on-screen yet (shouldn't happen once
        // the picker has resolved): bottom-right corner of the main display.
        guard let screen = NSScreen.main else { return .zero }
        let v = screen.visibleFrame
        return NSPoint(
            x: v.maxX - timerSize.width - 24,
            y: v.minY + 24
        )
    }

    private func clampToVisibleScreen(origin: NSPoint, size: NSSize) -> NSPoint {
        let candidate = NSRect(origin: origin, size: size)
        let screens = NSScreen.screens
        // If the candidate already overlaps any screen, keep it.
        if screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
            return origin
        }
        // Otherwise nudge it back onto the main screen's visible area.
        guard let screen = NSScreen.main else { return origin }
        let v = screen.visibleFrame
        let x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
        let y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    // MARK: - Character picker

    private func showCharacterPicker(library: [CharacterAssets],
                                     store: InstancesStore) {
        let controller = CharacterPickerWindowController()
        pickerController = controller
        controller.show(library: library) { [weak self, weak store] selectedID in
            store?.seedFirstCharacter(characterID: selectedID)
            self?.pickerController = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
