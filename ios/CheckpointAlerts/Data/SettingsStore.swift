import Foundation

/// Persisted user settings. UserDefaults, small, simple, and enough for a
/// handful of values. Same keys as the Android app where they overlap.
final class SettingsStore: ObservableObject {

    enum AlertScope: String {
        case wholeState = "WHOLE_STATE"
        case nearby = "NEARBY"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var stateCode: String {
        get { defaults.string(forKey: "state_code") ?? "TN" }
        set { defaults.set(newValue, forKey: "state_code") }
    }

    var scope: AlertScope {
        get {
            AlertScope(rawValue: defaults.string(forKey: "alert_scope") ?? "") ?? .wholeState
        }
        set { defaults.set(newValue.rawValue, forKey: "alert_scope") }
    }

    /// Home county for the NEARBY scope; blank when none picked yet.
    var homeCounty: String {
        get { defaults.string(forKey: "home_county") ?? "" }
        set { defaults.set(newValue, forKey: "home_county") }
    }

    var lastUpdatedMillis: Int64 {
        get { Int64(defaults.integer(forKey: "last_updated_ms")) }
        set { defaults.set(Int(newValue), forKey: "last_updated_ms") }
    }

    /// Master switch for day-of checkpoint alerts. On by default; the list
    /// still refreshes when it is off, it just never notifies.
    var notificationsEnabled: Bool {
        get {
            defaults.object(forKey: "notifications_enabled") as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: "notifications_enabled") }
    }

    /// Hourly reminders on checkpoint days: one digest notification an
    /// hour, 7 AM-10 PM, on days with a checkpoint in the user's area.
    /// On by default. Only ever notifies when the master
    /// [notificationsEnabled] switch is on too.
    var hourlyRemindersEnabled: Bool {
        get {
            defaults.object(forKey: "hourly_reminders_enabled") as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: "hourly_reminders_enabled") }
    }

    /// True once the app has asked for notification permission at least once,
    /// so first launch prompts but later launches don't nag.
    var notificationPromptShown: Bool {
        get { defaults.bool(forKey: "notif_prompt_shown") }
        set { defaults.set(newValue, forKey: "notif_prompt_shown") }
    }

    /// Checkpoint ids already notified about, for the given epoch day.
    /// Each checkpoint alerts once per day at most.
    func wasNotified(id: String, epochDay: Int) -> Bool {
        guard defaults.integer(forKey: "notify_epoch_day") == epochDay else { return false }
        return (defaults.stringArray(forKey: "notified_ids") ?? []).contains(id)
    }

    func markNotified(ids: [String], epochDay: Int) {
        var existing: [String]
        if defaults.integer(forKey: "notify_epoch_day") == epochDay {
            existing = defaults.stringArray(forKey: "notified_ids") ?? []
        } else {
            existing = []
        }
        for id in ids where !existing.contains(id) {
            existing.append(id)
        }
        defaults.set(epochDay, forKey: "notify_epoch_day")
        defaults.set(existing, forKey: "notified_ids")
    }
}

/// Whole days since 1970-01-01, for the per-day notified set.
func epochDay(for date: Date) -> Int {
    Int(date.timeIntervalSince1970 / 86_400)
}
