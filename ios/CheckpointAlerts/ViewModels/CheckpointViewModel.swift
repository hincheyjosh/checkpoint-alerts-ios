import Foundation
import SwiftUI

struct UiState {
    var checkpoints: [Checkpoint] = []
    var isRefreshing = false
    var lastUpdatedMillis: Int64 = 0
    var refreshError = false
    var lastError: String?
    var scope: SettingsStore.AlertScope = .wholeState
    var homeCounty = ""
    var showAll = false
    var notificationGranted = false
    var notificationsEnabled = true
    var hourlyRemindersEnabled = true
}

/// Mirrors the Android app's CheckpointViewModel: same state, same rules.
@MainActor
final class CheckpointViewModel: ObservableObject {

    @Published private(set) var uiState = UiState()

    private let settings: SettingsStore
    private let repository: CheckpointRepository
    private let notifications: NotificationManager
    private let background: BackgroundRefresh

    private var showAll = false

    init(
        settings: SettingsStore = SettingsStore(),
        repository: CheckpointRepository? = nil,
        notifications: NotificationManager = NotificationManager()
    ) {
        self.settings = settings
        self.repository = repository ?? CheckpointRepository(settings: settings)
        self.notifications = notifications
        self.background = BackgroundRefresh(
            repository: self.repository,
            settings: settings,
            notifications: notifications
        )
        background.register()
        background.schedule()
        uiState.scope = settings.scope
        uiState.homeCounty = settings.homeCounty
        uiState.notificationsEnabled = settings.notificationsEnabled
        uiState.hourlyRemindersEnabled = settings.hourlyRemindersEnabled
        uiState.lastUpdatedMillis = settings.lastUpdatedMillis
        let cached = self.repository.loadCache()
        applyCheckpoints(cached)
        Task { await refresh() }
        Task { await refreshNotificationStatus() }
    }

    /// Re-check whether notifications are granted. Call when the app
    /// comes back to the foreground, the user may just have changed it
    /// in the system settings.
    func refreshNotificationStatus() async {
        let status = await notifications.authorizationStatus()
        uiState.notificationGranted = (status == .authorized || status == .provisional)
    }

    /// Ask for notification permission once, on first launch. After that
    /// the in-app card handles re-asking.
    func requestNotificationPermissionIfNeeded() async {
        if uiState.notificationGranted { return }
        if settings.notificationPromptShown { return }
        settings.notificationPromptShown = true
        let granted = await notifications.requestAuthorization()
        uiState.notificationGranted = granted
    }

    func requestNotificationPermission() async {
        let granted = await notifications.requestAuthorization()
        uiState.notificationGranted = granted
    }

    func refresh() async {
        uiState.isRefreshing = true
        uiState.refreshError = false
        if let fresh = await repository.refresh() {
            applyCheckpoints(fresh)
            uiState.lastUpdatedMillis = settings.lastUpdatedMillis
            uiState.refreshError = false
            uiState.lastError = nil
            await rescheduleNotifications()
        } else {
            uiState.refreshError = true
            uiState.lastError = "couldn't refresh"
            applyCheckpoints(repository.loadCache())
        }
        uiState.isRefreshing = false
    }

    func setScope(_ scope: SettingsStore.AlertScope) {
        settings.scope = scope
        uiState.scope = scope
        applyCheckpoints(repository.loadCache())
        Task { await rescheduleNotifications() }
    }

    func setHomeCounty(_ county: String) {
        settings.homeCounty = county
        uiState.homeCounty = county
        applyCheckpoints(repository.loadCache())
        Task { await rescheduleNotifications() }
    }

    func setShowAll(_ showAll: Bool) {
        self.showAll = showAll
        uiState.showAll = showAll
        applyCheckpoints(repository.loadCache())
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        settings.notificationsEnabled = enabled
        uiState.notificationsEnabled = enabled
        Task {
            if enabled {
                await rescheduleNotifications()
            } else {
                await notifications.removeAllCheckpointNotifications()
            }
        }
    }

    func setHourlyRemindersEnabled(_ enabled: Bool) {
        settings.hourlyRemindersEnabled = enabled
        uiState.hourlyRemindersEnabled = enabled
        Task { await rescheduleNotifications() }
    }

    /// Rebuild the scheduled warnings from the current list and settings:
    /// drop day warnings for checkpoints out of scope, schedule the ones
    /// still owed, and rebuild the hourly digests.
    func rescheduleNotifications() async {
        let checkpoints = repository.loadCache()
        let today = startOfDay(Date())
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        var keepIds = Set<String>()
        for c in checkpoints where repository.inScope(c) {
            if calendar.isDate(c.date, inSameDayAs: today) {
                keepIds.insert("notify-\(c.id)-\(epochDay(for: today))")
            }
            if calendar.isDate(c.date, inSameDayAs: tomorrow) {
                keepIds.insert("notify-\(c.id)-\(epochDay(for: today))")
            }
        }
        await notifications.pruneDayWarnings(keepIds: keepIds)
        if settings.notificationsEnabled {
            await notifications.scheduleDayWarnings(
                checkpoints: checkpoints,
                settings: settings,
                inScope: { [weak self] c in self?.repository.inScope(c) ?? true }
            )
            await notifications.scheduleHourlyReminders(
                checkpoints: checkpoints,
                settings: settings,
                inScope: { [weak self] c in self?.repository.inScope(c) ?? true }
            )
        }
    }

    private func applyCheckpoints(_ all: [Checkpoint]) {
        let visible: [Checkpoint]
        if showAll {
            visible = all
        } else {
            visible = all.filter { inScope($0) }
        }
        uiState.checkpoints = visible
    }

    private func inScope(_ checkpoint: Checkpoint) -> Bool {
        if uiState.scope != .nearby { return true }
        if uiState.homeCounty.isEmpty { return true }
        return TnCounties.scopeCounties(homeCounty: uiState.homeCounty)
            .contains(checkpoint.county)
    }
}
