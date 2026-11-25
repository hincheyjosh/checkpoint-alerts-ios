import Foundation
import UserNotifications

/// Notifications for checkpoints happening today or tomorrow. Checkpoints
/// usually run around midnight, so the warning covers both days: a
/// checkpoint dated tomorrow warns today ("tomorrow") and again tomorrow
/// ("today"). One notification per checkpoint per day: a single checkpoint
/// gets a detailed notification; several get a short summary.
///
/// On iOS the warnings are scheduled ahead as local notifications (8 AM on
/// the warning day) and re-scheduled on every launch and refresh, because
/// iOS background work is best-effort and the system decides when the daily
/// check runs. The background refresh also posts immediately when it runs.
final class NotificationManager {

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Immediate posts (background refresh path)

    /// Post about [checkpoints] happening on [day], "today" or "tomorrow",
    /// which is what the titles say. A single checkpoint gets its own
    /// identifier so two immediate posts never clobber each other.
    func postCheckpoints(_ checkpoints: [Checkpoint], day: String) async {
        guard !checkpoints.isEmpty else { return }
        let content = contentFor(checkpoints, day: day)
        let id: String
        if checkpoints.count == 1 {
            id = "posted-\(checkpoints[0].id)-\(epochDay(for: Date()))"
        } else {
            id = "posted-\(day)-summary-\(epochDay(for: Date()))"
        }
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// Hourly digest for checkpoints happening today, one notification
    /// per hour, not one per checkpoint. Uses its own identifier so it
    /// never clobbers the once-per-day day-before/day-of notifications.
    func postHourly(_ checkpoints: [Checkpoint]) async {
        guard !checkpoints.isEmpty else { return }
        let content = contentFor(checkpoints, day: "today")
        let request = UNNotificationRequest(
            identifier: "posted-hourly-\(epochDay(for: Date()))",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // MARK: - Scheduled warnings (launch / refresh path)

    /// Schedule the day-before and day-of warnings for in-scope
    /// checkpoints dated today or tomorrow, at 8 AM on the warning day.
    /// Each checkpoint warns once per day at most, tracked in the
    /// settings notified set. If the 8 AM slot for the warning day has
    /// already passed (the app was opened late, or the checkpoint was
    /// only just announced), the warning goes out right away instead,
    /// the way the Android app posts when its daily check runs.
    func scheduleDayWarnings(
        checkpoints: [Checkpoint],
        settings: SettingsStore,
        inScope: (Checkpoint) -> Bool
    ) async {
        let today = startOfDay(Date())
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let now = Date()

        for checkpoint in checkpoints where inScope(checkpoint) {
            // "tomorrow" warning, delivered the day before.
            if calendar.isDate(checkpoint.date, inSameDayAs: tomorrow) {
                await warnOnce(
                    checkpoint: checkpoint,
                    day: "tomorrow",
                    warningDay: today,
                    settings: settings
                )
            }
            // "today" warning, delivered on the day.
            if calendar.isDate(checkpoint.date, inSameDayAs: today) {
                await warnOnce(
                    checkpoint: checkpoint,
                    day: "today",
                    warningDay: today,
                    settings: settings
                )
            }
        }

        func warnOnce(
            checkpoint: Checkpoint,
            day: String,
            warningDay: Date,
            settings: SettingsStore
        ) async {
            let epoch = epochDay(for: warningDay)
            guard !settings.wasNotified(id: checkpoint.id, epochDay: epoch) else { return }
            let id = "notify-\(checkpoint.id)-\(epoch)"
            if let fire = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: warningDay),
               fire > now {
                await schedule(
                    id: id,
                    content: contentFor([checkpoint], day: day),
                    date: fire
                )
            } else {
                // 8 AM has passed, send it now.
                await postCheckpoints([checkpoint], day: day)
            }
            settings.markNotified(ids: [checkpoint.id], epochDay: epoch)
        }
    }

    /// Schedule the hourly digests for days with a checkpoint in scope:
    /// one per hour, 7 AM-10 PM, for today and tomorrow. Any previously
    /// scheduled hourly digests are replaced, so a scope or toggle change
    /// takes effect right away.
    func scheduleHourlyReminders(
        checkpoints: [Checkpoint],
        settings: SettingsStore,
        inScope: (Checkpoint) -> Bool
    ) async {
        // Clear the old hourly schedule first.
        let pending = await center.pendingNotificationRequests()
        let hourlyIds = pending.map(\.identifier).filter { $0.hasPrefix("hourly-") }
        if !hourlyIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: hourlyIds)
        }
        guard settings.notificationsEnabled, settings.hourlyRemindersEnabled else { return }

        let calendar = Calendar.current
        let today = startOfDay(Date())
        let now = Date()
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            let todays = checkpoints.filter {
                calendar.isDate($0.date, inSameDayAs: day) && inScope($0)
            }
            guard !todays.isEmpty else { continue }
            for hour in 7...22 {
                guard let fire = calendar.date(
                    bySettingHour: hour, minute: 0, second: 0, of: day),
                      fire > now
                else { continue }
                let id = "hourly-\(epochDay(for: day))-\(hour)"
                await schedule(id: id, content: contentFor(todays, day: "today"), date: fire)
            }
        }
    }

    /// Remove every pending checkpoint notification, e.g. when alerts are
    /// turned off. Scheduled warnings are re-created on the next launch
    /// or refresh when alerts are back on.
    func removeAllCheckpointNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter {
            $0.hasPrefix("notify-") || $0.hasPrefix("hourly-") || $0.hasPrefix("posted-")
        }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Drop pending day warnings for checkpoints no longer in scope,
    /// keeping the warnings for the checkpoints in [keepIds]. Used when
    /// the alert scope changes: a warning already queued for a checkpoint
    /// that is still in scope stays put, and one for a checkpoint that
    /// fell out of scope goes away.
    func pruneDayWarnings(keepIds: Set<String>) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter {
            $0.hasPrefix("notify-") && !keepIds.contains($0)
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    // MARK: - Content

    private func contentFor(_ checkpoints: [Checkpoint], day: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if checkpoints.count == 1 {
            let c = checkpoints[0]
            content.title = "Checkpoint \(day) in \(c.county) County"
            content.body = "\(c.type.label) checkpoint, \(c.location)"
        } else {
            let counties = Array(Set(checkpoints.map(\.county))).sorted()
            let lines = checkpoints.sorted(by: { $0.county < $1.county }).prefix(3).map {
                "\($0.county) County, \($0.location)"
            }
            content.title = "\(checkpoints.count) checkpoints \(day)"
            content.body = "\(checkpoints.count) checkpoints \(day) in "
                + counties.joined(separator: ", ") + ":\n" + lines.joined(separator: "\n")
        }
        return content
    }

    private func schedule(id: String, content: UNNotificationContent, date: Date) async {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
