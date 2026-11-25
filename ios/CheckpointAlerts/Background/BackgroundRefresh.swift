import BackgroundTasks
import Foundation

/// Daily background refresh, the iOS equivalent of the Android app's
/// WorkManager jobs. iOS background work is best-effort: the system
/// decides when the task actually runs, and it may not run every day.
/// That is why the app also schedules its day-before/day-of warnings
/// ahead as local notifications (see NotificationManager) instead of
/// relying on the background task alone.
///
/// When the task does run it re-fetches the announcements, then notifies
/// once per checkpoint for any checkpoint happening today or tomorrow
/// inside the user's scope. Checkpoints usually run around midnight, so
/// the warning covers both days.
final class BackgroundRefresh {

    static let taskIdentifier = "com.checkpointalerts.app.refresh"

    private let repository: CheckpointRepository
    private let settings: SettingsStore
    private let notifications: NotificationManager

    init(
        repository: CheckpointRepository,
        settings: SettingsStore,
        notifications: NotificationManager
    ) {
        self.repository = repository
        self.settings = settings
        self.notifications = notifications
    }

    /// Register the task handler. Call once, early, at app launch.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier, using: nil
        ) { [weak self] task in
            guard let self, let task = task as? BGAppRefreshTask else { return }
            self.handle(task: task)
        }
    }

    /// Ask the system to run the refresh again in about a day.
    /// Best-effort, the system may run it later or not at all.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(task: BGAppRefreshTask) {
        schedule()
        let work = Task { [weak self] in
            guard let self else { return false }
            // Best effort: even if the refresh fails, last-known data may
            // still hold a checkpoint for today, so notify from whatever
            // we have.
            let fresh = await repository.refresh()
            let checkpoints = fresh ?? repository.loadCache()
            guard settings.notificationsEnabled else { return true }
            let today = startOfDay(Date())
            let toNotify = CheckpointRepository.selectToNotify(
                checkpoints: checkpoints,
                today: today,
                inScope: { [weak self] c in self?.repository.inScope(c) ?? true },
                wasNotified: { [weak self] id in
                    self?.settings.wasNotified(id: id, epochDay: epochDay(for: today)) ?? false
                }
            )
            let calendar = Calendar.current
            let todays = toNotify.filter { calendar.isDate($0.date, inSameDayAs: today) }
            let tomorrows = toNotify.filter {
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
                    return false
                }
                return calendar.isDate($0.date, inSameDayAs: tomorrow)
            }
            if !todays.isEmpty {
                await notifications.postCheckpoints(todays, day: "today")
            }
            if !tomorrows.isEmpty {
                await notifications.postCheckpoints(tomorrows, day: "tomorrow")
            }
            if !toNotify.isEmpty {
                settings.markNotified(ids: toNotify.map(\.id), epochDay: epochDay(for: today))
            }
            // Re-schedule the hourly digests from the fresh data.
            await notifications.scheduleHourlyReminders(
                checkpoints: checkpoints,
                settings: settings,
                inScope: { [weak self] c in self?.repository.inScope(c) ?? true }
            )
            return true
        }
        task.expirationHandler = {
            work.cancel()
        }
        Task {
            let ok = await work.value
            task.setTaskCompleted(success: ok)
        }
    }
}
