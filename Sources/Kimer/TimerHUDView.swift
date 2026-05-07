import SwiftUI

/// Compact pill that shows the active session phase + remaining time, or a
/// brief "DONE!" flash when a session just completed. Click handling is
/// delegated to the host panel; the context menu wires up start/pause/stop.
struct TimerHUDView: View {

    @ObservedObject var store: StudyTimerStore

    var body: some View {
        ZStack {
            background
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 120, minHeight: 48)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu { menu }
    }

    // MARK: - Visual

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.black.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
    }

    private var strokeColor: Color {
        if store.session?.isPaused == true { return .yellow.opacity(0.7) }
        if store.session?.phase == .focus  { return .green.opacity(0.7) }
        if store.session != nil            { return .blue.opacity(0.7) }
        return .white.opacity(0.2)
    }

    @ViewBuilder
    private var content: some View {
        if let s = store.session {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(s.isPaused ? Color.yellow : (s.phase == .focus ? .green : .blue))
                        .frame(width: 6, height: 6)
                    Text(s.isPaused ? "PAUSED" : s.phase.displayName.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .kerning(0.5)
                }
                Text(StudyTimerStore.formatMMSS(store.displayRemaining))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
        } else if store.lastCompletion != nil {
            VStack(spacing: 2) {
                Text("DONE!")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Today \(store.formattedTodayTotal())")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            Text("Kimer")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        StudyTimerMenu(store: store)
        Divider()
        Button("Quit Kimer") { NSApp.terminate(nil) }
    }
}

/// Reusable menu fragment so the character context menu and the timer HUD
/// surface the same controls.
struct StudyTimerMenu: View {

    @ObservedObject var store: StudyTimerStore

    var body: some View {
        Section("Study Timer") {
            if let s = store.session {
                Button(s.isPaused ? "Resume" : "Pause") {
                    store.pauseOrResume()
                }
                Button("Stop Session") {
                    store.stop()
                }
                Divider()
            }
            ForEach(StudyTimerStore.focusPresets, id: \.self) { mins in
                Button("Start \(mins) min focus") {
                    store.startFocus(minutes: mins)
                }
            }
            Button("Custom timer…") {
                CustomTimerPrompt.show { minutes in
                    store.startCustom(minutes: minutes)
                }
            }
        }
        Section {
            Text("Today: \(store.formattedTodayTotal())")
        }
    }
}
