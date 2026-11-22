import ActivityKit
import Foundation
import PolyplotCore
import UIKit
import UserNotifications

/// The task timer on the Lock Screen and in the Dynamic Island.
enum LiveActivities {
    /// A forgotten timer greys out this long after its planned end.
    static let staleAfter: TimeInterval = 30 * 60

    /// Shows the timer for `task` (replacing any other), picking up its elapsed time and pause state.
    static func start(task: PlannedTaskRecord, title: String) {
        let attributes = PolyplotTimerAttributes(
            taskTitle: title,
            sourceSymbol: TaskCopy.symbol(for: task.task),
            colorHex: task.task.hex
        )
        let content = self.content(for: task)
        Task {
            await endAllNow()
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }

    /// Refreshes the running timer after a pause or resume.
    static func update(task: PlannedTaskRecord) {
        let content = self.content(for: task)
        Task {
            for activity in Activity<PolyplotTimerAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    static func endAll() {
        Task { await endAllNow() }
    }

    static func endAllNow() async {
        for activity in Activity<PolyplotTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// For app termination: waits (briefly) until the timers are gone, since the process is about to end.
    static func endAllBlocking() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await endAllNow()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    private static func content(for task: PlannedTaskRecord) -> ActivityContent<PolyplotTimerAttributes.ContentState> {
        let now = Date.now
        let elapsed = task.elapsed(at: now)
        let effectiveStart = now.addingTimeInterval(-elapsed)
        let endsAt = effectiveStart.addingTimeInterval(Double(task.minutesPlanned * 60))
        let state = PolyplotTimerAttributes.ContentState(
            startedAt: effectiveStart,
            endsAt: endsAt,
            isPaused: task.isPaused,
            pausedElapsed: elapsed
        )
        return ActivityContent(state: state, staleDate: max(endsAt, now).addingTimeInterval(staleAfter))
    }
}

/// Notifications (docs/03-experience.md §3.7): a daily reminder at the learner's time, phrased around
/// their habit cue (R13), and an evening nudge on days with nothing logged yet.
enum Reminders {
    static let dailyPrefix = "polyplot.daily."
    /// The repeating reminder older versions scheduled; removed so it doesn't double up.
    static let legacyDailyID = "polyplot.daily"
    static let nudgePrefix = "polyplot.nudge."
    static let testID = "polyplot.test"
    static let nudgeHour = 20
    static let nudgeDaysAhead = 7
    /// Daily reminders are scheduled one by one, so each day's text can differ (a freeze used overnight).
    /// Rescheduled whenever the app changes anything; 30 days covers a long break (iOS allows 64 pending).
    static let dailyDaysAhead = 30

    /// What a day's reminder says when a streak freeze covered the day before.
    struct FreezeNote {
        var streak: Int
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Asks only if the learner has never been asked on this phone. Onboarding asks when the reminder is
    /// switched on, but a learner who skipped onboarding (restored a backup, or data already there) never was.
    static func requestPermissionIfUndecided() async -> Bool {
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined else { return false }
        return await requestPermission()
    }

    /// Every reminder and nudge Polyplot schedules (older versions numbered them by days ahead; now each
    /// carries its date, e.g. "polyplot.daily.2026-11-22"), but not the test notification.
    private static func isReminder(_ id: String) -> Bool {
        id == legacyDailyID || id.hasPrefix(dailyPrefix) || id.hasPrefix(nudgePrefix)
    }

    /// One identifier per day, so a new reminder never reuses the identifier of one still in Notification Centre.
    private static func identifier(_ prefix: String, for day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return prefix + String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Refreshes run one after another, so a quick second one can't interleave with the first.
    @MainActor private static var lastRefresh: Task<Void, Never>?

    /// Reschedules everything. Called after anything that changes the reminder settings or today's practice.
    /// `freezeNote` says, for a day, whether a freeze will have covered the day before if nothing more is logged.
    /// What's left of today's plan when it's been started but not finished, for tonight's nudge.
    struct UnfinishedPlan {
        let doneMinutes: Int
        let tasksLeft: Int
        let minutesLeft: Int
    }

    /// `practisedToday`: something has been logged today (the plan has started). Then today's reminder isn't sent,
    /// and any reminder or nudge already in Notification Centre is removed.
    /// `unfinished` (today's plan, started but not finished) turns tonight's nudge into one about finishing it.
    @MainActor
    static func refresh(for profile: LearnerProfile, practisedToday: Bool, unfinished: UnfinishedPlan? = nil, calendar: Calendar = .current,
                        freezeNote: (Date) -> FreezeNote? = { _ in nil }) {
        let requests = profile.reminderEnabled
            ? makeRequests(for: profile, practisedToday: practisedToday, unfinished: unfinished, calendar: calendar, freezeNote: freezeNote)
            : []
        let previous = lastRefresh
        lastRefresh = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            // Clear first, then schedule: a delivered reminder is removed before anything new is added.
            if practisedToday { await removeDelivered(center) }
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter(isReminder)
            center.removePendingNotificationRequests(withIdentifiers: pending)
            for request in requests { try? await center.add(request) }
        }
    }

    private static func makeRequests(for profile: LearnerProfile, practisedToday: Bool, unfinished: UnfinishedPlan?, calendar: Calendar,
                                     freezeNote: (Date) -> FreezeNote?) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let now = Date.now
        // Reminders are for the language being learned: its name and its own words.
        let pack = profile.pack
        // Today's reminder only while nothing has been logged today: once the plan has started, it has done its job.
        for offset in (practisedToday ? 1 : 0)..<dailyDaysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(bySettingHour: profile.reminderHour, minute: profile.reminderMinute, second: 0, of: day),
                  fireDate > now else { continue }
            let daily = UNMutableNotificationContent()
            if let note = freezeNote(fireDate) {
                daily.title = "🧊 Streak freeze used"
                daily.body = "Your \(note.streak)-day streak is safe. A little \(pack.name) today keeps it going."
            } else {
                daily.title = pack.phrases(for: profile.band).reminderTitle
                daily.body = "Poly has today's plan ready. Even 10 minutes counts."
            }
            daily.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            requests.append(UNNotificationRequest(identifier: identifier(dailyPrefix, for: fireDate, calendar: calendar), content: daily,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }

        // Evening nudges for the coming week. Once something has been logged today, today's is either
        // about finishing a plan that's been started, or skipped (the plan's done, or there isn't one).
        for offset in 0..<nudgeDaysAhead {
            let finishing = offset == 0 && practisedToday ? unfinished : nil
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(bySettingHour: nudgeHour, minute: 0, second: 0, of: day),
                  fireDate > now,
                  !(offset == 0 && practisedToday && finishing == nil),
                  // Don't nudge before the daily reminder has even had its turn.
                  profile.reminderHour < nudgeHour
            else { continue }
            let nudge = UNMutableNotificationContent()
            if let finishing {
                let tasks = finishing.tasksLeft == 1 ? "One task" : "\(finishing.tasksLeft) tasks"
                nudge.title = "So close 🌙"
                nudge.body = "You've done \(finishing.doneMinutes) min today. \(tasks) (about \(finishing.minutesLeft) min) and today's plan is finished."
            } else {
                nudge.title = "Poly's still awake 🌙"
                nudge.body = "Nothing logged today yet. Even one quick lesson keeps your streak going."
            }
            nudge.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            requests.append(UNNotificationRequest(identifier: identifier(nudgePrefix, for: fireDate, calendar: calendar), content: nudge,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
        return requests
    }

    /// Removes reminders and nudges already shown in Notification Centre, once something has been logged today.
    private static func removeDelivered(_ center: UNUserNotificationCenter) async {
        let ids = await center.deliveredNotifications().map(\.request.identifier).filter(isReminder)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// A notification in 5 seconds, to check notifications reach the phone.
    static func sendTest() async -> Bool {
        guard await requestPermission() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "\(ActiveLanguage.phrases.hello) 🐦"
        content.body = "Notifications from Polyplot are working."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: testID, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        )
        return true
    }

    @MainActor
    static func cancel() {
        let previous = lastRefresh
        lastRefresh = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter(isReminder)
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
    }
}

/// Without a delegate, iOS hides an app's notifications while that app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// Opens the source app for a task, falling back to the web. Each language's sources say how they open
/// (`SourceInfo.appURL`, `webURL`); the Spanish schemes were confirmed on device in M0.
enum DeepLinks {
    static func url(for task: TaskKind, detail: TaskDetail) -> URL? {
        let pack = ActiveLanguage.pack
        switch task {
        case .seriesIntensive, .seriesExtensive:
            // The learner series is on YouTube: search for the episode.
            guard let series = pack.series else { return nil }
            let episode: Int = switch detail {
            case .seriesPart(let episode, _), .seriesEpisode(let episode): episode
            default: 1
            }
            let query = "\(series.searchPrefix) \(episode)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "https://www.youtube.com/results?search_query=\(query)")
        default:
            return task.source.flatMap { pack.sources[$0]?.appURL }.flatMap(URL.init(string:))
        }
    }

    static func webFallback(for task: TaskKind) -> URL? {
        task.source.flatMap { ActiveLanguage.pack.sources[$0]?.webURL }.flatMap(URL.init(string:))
    }

    @MainActor
    static func open(_ task: TaskKind, detail: TaskDetail) {
        guard let url = url(for: task, detail: detail) else { return }
        UIApplication.shared.open(url) { opened in
            if !opened, let fallback = webFallback(for: task) {
                UIApplication.shared.open(fallback)
            }
        }
    }
}
