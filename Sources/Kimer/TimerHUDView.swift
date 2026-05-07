import SwiftUI

/// Compact pill anchored under the character. Monotone — solid dark gray
/// background, white text, ⏱ leading glyph. Click on the host panel toggles
/// pause/resume; right-click opens the full study-timer menu.
struct TimerHUDView: View {

    @ObservedObject var store: StudyTimerStore

    var body: some View {
        ZStack {
            background
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu { menu }
    }

    // MARK: - Visual

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(white: 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private var content: some View {
        if let s = store.session {
            HStack(spacing: 10) {
                Text("⏱")
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(StudyTimerStore.formatMMSS(store.displayRemaining))
                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(s.isPaused ? "PAUSED" : s.phase.displayName.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
        } else if store.lastCompletion != nil {
            HStack(spacing: 8) {
                Text("⏱")
                    .font(.system(size: 18))
                Text("DONE")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 8) {
                Text("⏱")
                    .font(.system(size: 16))
                Text("Kimer")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }
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
