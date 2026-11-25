import SwiftUI

@main
struct CheckpointAlertsApp: App {

    @StateObject private var viewModel: CheckpointViewModel

    init() {
        // Creating the view model here registers the background refresh
        // task before the app finishes launching, which is when iOS
        // expects BGTaskScheduler registration to happen.
        _viewModel = StateObject(wrappedValue: CheckpointViewModel())
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    Task { await viewModel.requestNotificationPermissionIfNeeded() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await viewModel.refreshNotificationStatus() }
                    }
                }
        }
    }
}
