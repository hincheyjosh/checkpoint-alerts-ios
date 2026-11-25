import Foundation

struct RepoState {
    var checkpoints: [Checkpoint] = []
    var isRefreshing = false
    var lastUpdatedMillis: Int64 = 0
    /// True when the last refresh failed and the list is last-known data.
    var refreshError = false
    /// Why the last refresh failed (HTTP code, exception, parse), if it did.
    var lastError: String?
}

/// Owns fetching, caching, and scope filtering of checkpoints.
final class CheckpointRepository {

    private let settings: SettingsStore
    private let source = TennesseeSource()

    private var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("checkpoints.json")
    }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Counties the user's scope covers, or nil for the whole state.
    func scopeCounties() -> Set<String>? {
        guard settings.scope == .nearby else { return nil }
        let home = settings.homeCounty
        guard !home.isEmpty else { return nil }
        return TnCounties.scopeCounties(homeCounty: home)
    }

    func inScope(_ checkpoint: Checkpoint) -> Bool {
        guard let counties = scopeCounties() else { return true }
        return counties.contains(checkpoint.county)
    }

    /// Load the saved cache (if any) so the list is never empty on launch.
    func loadCache() -> [Checkpoint] {
        readCache()
    }

    /// Re-fetch from the source. On failure the last saved list stays put
    /// and the caller sets refreshError, the UI says so plainly.
    /// Returns the fresh list on success, nil on failure.
    func refresh() async -> [Checkpoint]? {
        do {
            let fresh = try await source.fetch()
            writeCache(fresh)
            settings.lastUpdatedMillis = Int64(Date().timeIntervalSince1970 * 1000)
            return fresh
        } catch {
            return nil
        }
    }

    /// Which in-scope checkpoints to warn about on [today]: those dated
    /// today or tomorrow. A checkpoint warned about as "tomorrow" warns
    /// again as "today", the per-day notified set makes that happen
    /// naturally, since [wasNotified] is asked about today only.
    static func selectToNotify(
        checkpoints: [Checkpoint],
        today: Date,
        inScope: (Checkpoint) -> Bool,
        wasNotified: (String) -> Bool
    ) -> [Checkpoint] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay(today)) ?? today
        return checkpoints.filter {
            (calendar.isDate($0.date, inSameDayAs: today)
                || calendar.isDate($0.date, inSameDayAs: tomorrow))
                && inScope($0) && !wasNotified($0.id)
        }
    }

    /// Which in-scope checkpoints dated [today] earn an hourly digest
    /// right now: all gates must hold, the master notifications switch
    /// is on, the hourly toggle is on, the current hour is within
    /// 7 AM-10 PM, and at least one checkpoint dated today is in scope.
    static func selectTodays(
        checkpoints: [Checkpoint],
        today: Date,
        hour: Int,
        notificationsEnabled: Bool,
        hourlyRemindersEnabled: Bool,
        inScope: (Checkpoint) -> Bool
    ) -> [Checkpoint] {
        guard notificationsEnabled else { return [] }
        guard hourlyRemindersEnabled else { return [] }
        guard hour >= 7 && hour <= 22 else { return [] }
        return checkpoints.filter {
            Calendar.current.isDate($0.date, inSameDayAs: today) && inScope($0)
        }
    }

    private func readCache() -> [Checkpoint] {
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoded = try JSONDecoder().decode([Checkpoint].self, from: data)
            let today = startOfDay(Date())
            return decoded
                .filter { $0.date >= today }
                .sorted {
                    if $0.date != $1.date { return $0.date < $1.date }
                    if $0.county != $1.county { return $0.county < $1.county }
                    return $0.location < $1.location
                }
        } catch {
            return []
        }
    }

    private func writeCache(_ list: [Checkpoint]) {
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache write failure is non-fatal; the in-memory list still works.
        }
    }
}
