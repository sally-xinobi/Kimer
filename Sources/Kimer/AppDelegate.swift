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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background-style app: no Dock icon, no menu bar item.
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
        panel.onMove = { [weak instance] newOrigin in
            instance?.updateOrigin(newOrigin)
        }

        panel.orderFrontRegardless()
        panels[instance.id] = panel

        // Resize the panel whenever this instance's size changes.
        sizeCancellables[instance.id] = instance.$sizeRaw
            .removeDuplicates()
            .dropFirst()
            .sink { [weak panel, weak instance] _ in
                guard let panel, let instance else { return }
                panel.applySize(instance.size.nsSize)
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
            let origin = TimerPanel.savedOrigin() ?? TimerPanel.defaultOrigin()
            let frame = NSRect(origin: origin, size: TimerPanel.defaultSize)
            let panel = TimerPanel(initialFrame: frame)
            let view = TimerHUDView(store: timerStore)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: TimerPanel.defaultSize)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.onMove = { newOrigin in
                TimerPanel.saveOrigin(newOrigin)
            }
            panel.onClick = { [weak timerStore] in
                // Click toggles pause/resume when a session is active. When no
                // session, the click is a no-op — discovery happens via the
                // right-click menu.
                guard let timerStore, timerStore.session != nil else { return }
                timerStore.pauseOrResume()
            }
            timerPanel = panel
            timerHostingView = host
        }
        timerPanel?.orderFrontRegardless()
    }

    private func hideTimerHUD() {
        timerPanel?.orderOut(nil)
        timerPanel = nil
        timerHostingView = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
