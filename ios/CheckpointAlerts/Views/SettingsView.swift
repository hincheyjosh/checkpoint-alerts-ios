import SwiftUI

private let settingsDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "MMM d, h:mm a"
    return f
}()

struct SettingsView: View {

    var uiState: UiState
    var onScopeChange: (SettingsStore.AlertScope) -> Void
    var onCountyChange: (String) -> Void
    var onNotificationsEnabledChange: (Bool) -> Void
    var onHourlyRemindersEnabledChange: (Bool) -> Void
    var onRequestNotificationPermission: () -> Void
    var onRefresh: () -> Void

    @State private var showCountyPicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("State") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tennessee")
                        .font(.body)
                    Text("More states coming soon, each state gets its own source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Alert scope") {
                ScopeRadioRow(
                    selected: uiState.scope == .wholeState,
                    title: "Whole state",
                    subtitle: "Alerts for any checkpoint in Tennessee",
                    onSelect: { onScopeChange(.wholeState) }
                )
                ScopeRadioRow(
                    selected: uiState.scope == .nearby,
                    title: "My county + nearby counties",
                    subtitle: "Alerts for checkpoints in your county and the counties touching it",
                    onSelect: { onScopeChange(.nearby) }
                )
                if uiState.scope == .nearby {
                    Button(action: { showCountyPicker = true }) {
                        Text(uiState.homeCounty.isEmpty
                            ? "Choose your county"
                            : "\(uiState.homeCounty) County")
                    }
                    .buttonStyle(.bordered)
                    if uiState.homeCounty.isEmpty {
                        Text("Pick your county to turn on nearby alerts. Until then, the whole state is shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        let covered = TnCounties.scopeCounties(homeCounty: uiState.homeCounty).sorted()
                        Text("Covered counties: " + covered.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Notifications") {
                Toggle(isOn: Binding(
                    get: { uiState.notificationsEnabled },
                    set: onNotificationsEnabledChange
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checkpoint alerts")
                        Text("Notify me the day before and the day a checkpoint happens in my area")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(
                    get: { uiState.hourlyRemindersEnabled },
                    set: onHourlyRemindersEnabledChange
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hourly reminders on checkpoint days")
                        Text("Every hour, 7 AM-10 PM, on days with a checkpoint in your area")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!uiState.notificationsEnabled)
                if !uiState.notificationsEnabled {
                    Text("Alerts are turned off. The list still updates when you open the app, you just won't be notified.")
                } else if uiState.notificationGranted {
                    Text("Notifications are on. You'll be alerted the day before and the day a checkpoint happens in your area.")
                } else {
                    Text("Notifications are off. Without them, the app can only show checkpoints when you open it.")
                    Button("Turn on notifications", action: onRequestNotificationPermission)
                        .buttonStyle(.borderedProminent)
                }
            }

            Section("Background refresh") {
                Text("iOS decides when the daily check runs in the background, and it may not run every day. The app also schedules your day-before and day-of warnings ahead of time, so they still go out even if the background check doesn't run.")
                    .font(.subheadline)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Text("In the system Settings, turn on Background App Refresh for this app to give the daily check the best chance of running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About this data") {
                Text("Checkpoint listings come straight from the Tennessee Highway Patrol's office.")
            }

            Section {
                let lastUpdated = uiState.lastUpdatedMillis > 0
                    ? "Last checked \(settingsDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(uiState.lastUpdatedMillis) / 1000)))"
                    : "Never checked yet"
                Text(lastUpdated)
                Button("Check now", action: onRefresh)
                    .buttonStyle(.bordered)
                if uiState.refreshError {
                    Text("The last check failed"
                        + (uiState.lastError.map { " (\($0))" } ?? "")
                        + ", showing last saved checkpoints.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Checkpoint Alerts v1.0, Tennessee only for now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                MadeWithLoveFooter()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showCountyPicker) {
            CountyPickerView(
                selected: uiState.homeCounty,
                onSelect: { onCountyChange($0) }
            )
        }
    }
}

struct ScopeRadioRow: View {

    var selected: Bool
    var title: String
    var subtitle: String
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

struct CountyPickerView: View {

    var selected: String
    var onSelect: (String) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [String] {
        if query.isEmpty {
            return TnCounties.all
        }
        return TnCounties.all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { county in
                Button(action: {
                    onSelect(county)
                    dismiss()
                }) {
                    HStack {
                        Text("\(county) County")
                            .foregroundStyle(.primary)
                        Spacer()
                        if county == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search counties")
            .navigationTitle("Choose your county")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
