import SwiftUI

private let listDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "EEE, MMM d"
    return f
}()

private let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "EEE"
    return f
}()

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "h:mm a"
    return f
}()

func dateLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInTomorrow(date) { return "Tomorrow" }
    return listDateFormatter.string(from: date)
}

func lastUpdatedText(_ millis: Int64) -> String {
    if millis <= 0 { return "Never updated yet" }
    let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    return "Last updated \(timeFormatter.string(from: date))"
}

struct HomeView: View {

    var uiState: UiState
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onSelect: (Checkpoint) -> Void
    var onToggleShowAll: () -> Void
    var onRequestNotificationPermission: () -> Void

    private var today: [Checkpoint] {
        uiState.checkpoints.filter(\.isToday)
    }

    private var upcoming: [Checkpoint] {
        uiState.checkpoints.filter { !$0.isToday }
    }

    var body: some View {
        List {
            if !uiState.notificationGranted {
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "bell")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Turn on notifications")
                                .font(.headline)
                            Text("We'll alert you the day before and the day a checkpoint happens in your area.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Turn on", action: onRequestNotificationPermission)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alert scope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if uiState.scope == .wholeState {
                            Text("Whole state, every checkpoint in Tennessee")
                        } else if uiState.homeCounty.isEmpty {
                            Text("My county + nearby, pick your county in Settings")
                        } else {
                            let covered = TnCounties.scopeCounties(homeCounty: uiState.homeCounty).count
                            Text("\(uiState.homeCounty) County + nearby (\(covered) counties)")
                        }
                    }
                    Spacer()
                    Button("Change", action: onOpenSettings)
                }
                .padding(.vertical, 4)
            }

            if !today.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(today.count == 1
                            ? "1 checkpoint today in your area"
                            : "\(today.count) checkpoints today in your area")
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.red.opacity(0.12))
                    ForEach(today) { checkpoint in
                        CheckpointRow(checkpoint: checkpoint, highlight: true)
                            .onTapGesture { onSelect(checkpoint) }
                    }
                }
            }

            Section {
                HStack {
                    Text("Upcoming")
                        .font(.headline)
                    Spacer()
                    if uiState.scope == .nearby {
                        Button(action: onToggleShowAll) {
                            Text("All Tennessee")
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    uiState.showAll
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if today.isEmpty && upcoming.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("No checkpoints announced")
                            .font(.headline)
                        Text("Nothing in your area right now. New announcements appear through the week, check back later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(upcoming) { checkpoint in
                        CheckpointRow(checkpoint: checkpoint, highlight: false)
                            .onTapGesture { onSelect(checkpoint) }
                    }
                }
            }

            Section {
                VStack(spacing: 4) {
                    Text(lastUpdatedText(uiState.lastUpdatedMillis))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if uiState.refreshError {
                        Text("Couldn't refresh"
                            + (uiState.lastError.map { " (\($0))" } ?? "")
                            + ", showing last saved checkpoints. Tap refresh to try again.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                MadeWithLoveFooter()
            }
        }
        .navigationTitle("Checkpoint Alerts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(uiState.isRefreshing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .refreshable { onRefresh() }
    }
}

struct CheckpointRow: View {

    var checkpoint: Checkpoint
    var highlight: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(weekdayFormatter.string(from: checkpoint.date).uppercased())
                    .font(.caption)
                    .foregroundStyle(.accent)
                Text("\(Calendar.current.component(.day, from: checkpoint.date))")
                    .font(.title2)
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(checkpoint.location)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    TypeBadge(type: checkpoint.type)
                    Text("\(checkpoint.county) County")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(dateLabel(checkpoint.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(highlight ? Color.accentColor.opacity(0.12) : nil)
    }
}

struct TypeBadge: View {

    var type: CheckpointType

    var body: some View {
        Text(type.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                type == .sobriety
                    ? Color.red.opacity(0.18)
                    : Color.secondary.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(type == .sobriety ? .red : .secondary)
    }
}
