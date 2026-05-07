import Foundation
import Combine

enum TypingState: Equatable {
    case idle
    case running
}

/// Aggregates global keystroke events into a public `state` (idle/running)
/// and a smoothed characters-per-second value. Drives the on-screen character.
final class TypingSpeedTracker: ObservableObject {

    /// Time without input after which the tracker flips back to `.idle`.
    private let idleThreshold: TimeInterval = 0.5

    /// How many recent timestamps to retain for CPS calculation.
    private let bufferCapacity = 16

    /// Only the last N samples are used for the actual CPS computation, so the
    /// readout responds to recent acceleration rather than the long-term average.
    private let cpsWindow = 8

    @Published private(set) var state: TypingState = .idle
    @Published private(set) var cps: Double = 0

    private var timestamps: [TimeInterval] = []
    private var lastKeystrokeAt: TimeInterval = 0
    private var idleTimer: Timer?

    init() {
        // Periodic check so we transition back to .idle without a new keystroke.
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.evaluateIdleTransition()
        }
    }

    deinit {
        idleTimer?.invalidate()
    }

    func recordKeystroke() {
        let now = Date().timeIntervalSinceReferenceDate
        if Thread.isMainThread {
            applyKeystroke(at: now)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyKeystroke(at: now)
            }
        }
    }

    private func applyKeystroke(at now: TimeInterval) {
        timestamps.append(now)
        if timestamps.count > bufferCapacity {
            timestamps.removeFirst(timestamps.count - bufferCapacity)
        }
        lastKeystrokeAt = now

        let newCPS = computeCPS()
        // Coalesce small changes — every keystroke would otherwise re-render
        // SwiftUI and re-set the player rate on AVPlayer.
        if abs(newCPS - cps) > 0.15 {
            cps = newCPS
        }

        if state != .running {
            state = .running
        }
    }

    private func computeCPS() -> Double {
        guard timestamps.count >= 2 else { return 0 }
        let recent = timestamps.suffix(cpsWindow)
        guard let first = recent.first, let last = recent.last else { return 0 }
        let span = last - first
        guard span > 0 else { return 0 }
        return Double(recent.count - 1) / span
    }

    private func evaluateIdleTransition() {
        guard state == .running else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastKeystrokeAt > idleThreshold {
            state = .idle
            cps = 0
        }
    }
}
