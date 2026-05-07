import Foundation
import AppKit
import Combine
import UserNotifications

/// Phase of an active study session.
enum StudyPhase: String, Codable {
    case focus
    case shortBreak
    case longBreak

    var displayName: String {
        switch self {
        case .focus:      return "Focus"
        case .shortBreak: return "Break"
        case .longBreak:  return "Long Break"
        }
    }
}

/// One running session — either ticking or paused.
struct StudySession: Codable, Equatable {
    var phase: StudyPhase
    var totalDuration: TimeInterval     // total seconds the session was started for
    var startedAt: Date                 // when the current run leg began
    var elapsedBeforePause: TimeInterval // seconds counted before the most recent pause
    var pausedAt: Date?                 // nil when running

    var isPaused: Bool { pausedAt != nil }

    /// Seconds elapsed including the current run leg if not paused.
    func elapsed(now: Date) -> TimeInterval {
        if isPaused {
            return elapsedBeforePause
        }
        return elapsedBeforePause + max(0, now.timeIntervalSince(startedAt))
    }

    func remaining(now: Date) -> TimeInterval {
        max(0, totalDuration - elapsed(now: now))
    }
}

/// App-wide owner of the active study session, daily totals, and the per-session
/// completion lifecycle (notification + chime + auto-clear).
final class StudyTimerStore: ObservableObject {

    @Published private(set) var session: StudySession?
    @Published private(set) var displayRemaining: TimeInterval = 0
    @Published private(set) var todayFocusSeconds: TimeInterval = 0

    /// Last completed session — UI flashes "DONE!" briefly when this changes.
    @Published private(set) var lastCompletion: Date?

    private static let sessionKey = "kimer.activeSession"
    private static let dailyKey   = "kimer.dailyFocus"   // [yyyy-mm-dd: seconds]

    private var ticker: Timer?
    private var notificationsRequested = false

    // Pomodoro presets (focus durations in minutes).
    static let focusPresets: [Int] = [15, 25, 50]

    init() {
        restoreSession()
        recomputeDailyTotal()
        startTicker()
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: - Public controls

    func startFocus(minutes: Int) {
        startSession(phase: .focus, duration: TimeInterval(minutes) * 60)
    }

    func startCustom(minutes: Int, phase: StudyPhase = .focus) {
        let clamped = max(1, min(minutes, 600))
        startSession(phase: phase, duration: TimeInterval(clamped) * 60)
    }

    func pauseOrResume() {
        guard var current = session else { return }
        let now = Date()
        if current.isPaused {
            // Resume: shift startedAt to now; elapsedBeforePause stays.
            current.pausedAt = nil
            current.startedAt = now
        } else {
            // Pause: bank elapsed leg into elapsedBeforePause.
            current.elapsedBeforePause += max(0, now.timeIntervalSince(current.startedAt))
            current.pausedAt = now
        }
        session = current
        persistSession()
        refreshDisplay()
    }

    func stop() {
        guard let current = session else { return }
        // Bank elapsed focus time into today's total (only for focus phase).
        if current.phase == .focus {
            let banked = current.elapsed(now: Date())
            addFocusSeconds(banked)
        }
        session = nil
        persistSession()
        refreshDisplay()
        cancelScheduledCompletionNotification()
    }

    // MARK: - Tick loop

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshDisplay()
        }
    }

    private func refreshDisplay() {
        let now = Date()
        if let current = session {
            let rem = current.remaining(now: now)
            if rem != displayRemaining {
                displayRemaining = rem
            }
            if rem <= 0 {
                completeSession()
            }
        } else {
            if displayRemaining != 0 {
                displayRemaining = 0
            }
        }
    }

    private func completeSession() {
        guard let current = session else { return }
        if current.phase == .focus {
            addFocusSeconds(current.totalDuration)
        }
        session = nil
        lastCompletion = Date()
        persistSession()
        playChime()
        postCompletionNotificationNow(phase: current.phase)
    }

    // MARK: - Session start

    private func startSession(phase: StudyPhase, duration: TimeInterval) {
        let now = Date()
        // If a session is already running, treat as a fresh start: bank focus
        // time so partial work isn't lost.
        if let prev = session, prev.phase == .focus {
            addFocusSeconds(prev.elapsed(now: now))
        }
        session = StudySession(
            phase: phase,
            totalDuration: duration,
            startedAt: now,
            elapsedBeforePause: 0,
            pausedAt: nil
        )
        persistSession()
        refreshDisplay()
        scheduleCompletionNotification(after: duration, phase: phase)
    }

    // MARK: - Daily totals

    func formattedTodayTotal() -> String {
        Self.formatHMS(todayFocusSeconds)
    }

    private func recomputeDailyTotal() {
        let map = readDailyMap()
        todayFocusSeconds = map[Self.todayKey()] ?? 0
    }

    private func addFocusSeconds(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        var map = readDailyMap()
        let key = Self.todayKey()
        map[key, default: 0] += seconds
        // Trim to last 30 days so the dictionary stays small.
        if map.count > 30 {
            let sortedKeys = map.keys.sorted()
            for k in sortedKeys.prefix(map.count - 30) {
                map.removeValue(forKey: k)
            }
        }
        writeDailyMap(map)
        todayFocusSeconds = map[key] ?? 0
    }

    private func readDailyMap() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: Self.dailyKey),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        return decoded
    }

    private func writeDailyMap(_ map: [String: TimeInterval]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.dailyKey)
        }
    }

    // MARK: - Persistence

    private func persistSession() {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        }
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionKey),
              let decoded = try? JSONDecoder().decode(StudySession.self, from: data)
        else { return }
        // If the restored session has already elapsed past completion while the
        // app was closed, bank its focus time and complete silently — we don't
        // want to spam a notification for a session that ended hours ago.
        let now = Date()
        if decoded.remaining(now: now) <= 0 {
            if decoded.phase == .focus {
                addFocusSeconds(decoded.totalDuration)
            }
            session = nil
            return
        }
        session = decoded
    }

    // MARK: - Notifications + chime

    func ensureNotificationAuthorization() {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Best effort — failure is non-fatal; the chime + on-screen chip
            // already convey completion.
        }
    }

    private func scheduleCompletionNotification(after seconds: TimeInterval, phase: StudyPhase) {
        cancelScheduledCompletionNotification()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "Focus complete" : "Break over"
        content.body  = phase == .focus
            ? "Nice work — time for a break."
            : "Back to focus when you're ready."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let req = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func cancelScheduledCompletionNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// Fired in the foreground path (timer wound down while app was running).
    /// We always post immediately — the scheduled trigger is the safety net for
    /// when the app is backgrounded or sleep cancels Timer scheduling.
    private func postCompletionNotificationNow(phase: StudyPhase) {
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "Focus complete" : "Break over"
        content.body  = phase == .focus
            ? "Nice work — time for a break."
            : "Back to focus when you're ready."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: Self.notificationID + ".now",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func playChime() {
        // Glass is a neutral, unobtrusive system sound; falls back silently if
        // the user disabled system sounds.
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    private static let notificationID = "kimer.session.complete"

    // MARK: - Helpers

    static func formatMMSS(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let m = s / 60
        let r = s % 60
        if s >= 3600 {
            let h = s / 3600
            let mm = (s % 3600) / 60
            return String(format: "%d:%02d:%02d", h, mm, r)
        }
        return String(format: "%d:%02d", m, r)
    }

    static func formatHMS(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    private static func todayKey(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
