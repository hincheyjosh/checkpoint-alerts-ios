import SwiftUI

/// Root navigation: Home, with Settings as a sheet and a detail screen
/// for one checkpoint.
struct ContentView: View {

    @ObservedObject var viewModel: CheckpointViewModel
    @State private var showSettings = false
    @State private var selected: Checkpoint?

    var body: some View {
        NavigationStack {
            HomeView(
                uiState: viewModel.uiState,
                onRefresh: { Task { await viewModel.refresh() } },
                onOpenSettings: { showSettings = true },
                onSelect: { selected = $0 },
                onToggleShowAll: { viewModel.setShowAll(!viewModel.uiState.showAll) },
                onRequestNotificationPermission: {
                    Task { await viewModel.requestNotificationPermission() }
                }
            )
            .navigationDestination(item: $selected) { checkpoint in
                DetailView(checkpoint: checkpoint)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(
                        uiState: viewModel.uiState,
                        onScopeChange: { viewModel.setScope($0) },
                        onCountyChange: { viewModel.setHomeCounty($0) },
                        onNotificationsEnabledChange: { viewModel.setNotificationsEnabled($0) },
                        onHourlyRemindersEnabledChange: { viewModel.setHourlyRemindersEnabled($0) },
                        onRequestNotificationPermission: {
                            Task { await viewModel.requestNotificationPermission() }
                        },
                        onRefresh: { Task { await viewModel.refresh() } }
                    )
                }
            }
        }
    }
}
