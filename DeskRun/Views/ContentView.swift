import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable {
    case dashboard = "Dashboard"
    case connection = "Connection"
    case goals = "Goals"
    case history = "History"
    case settings = "Settings"
}

struct ContentView: View {
    let appState: AppState

    @State private var selectedItem: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selectedItem) { item in
                sidebarLabel(for: item)
            }
            .navigationTitle("DeskRun")
            .listStyle(.sidebar)
        } detail: {
            switch selectedItem {
            case .dashboard:
                DashboardView(appState: appState)
            case .connection:
                ConnectionView(state: appState.treadmillState, bleManager: appState.bleManager)
            case .goals:
                GoalsView(appState: appState)
            case .history:
                HistoryView(appState: appState)
            case .settings:
                SettingsView(appState: appState)
            case .none:
                DashboardView(appState: appState)
            }
        }
        .frame(minWidth: 750, minHeight: 550)
        .onChange(of: appState.treadmillState.connectionStatus) { oldValue, newValue in
            if newValue == .connected && oldValue != .connected {
                selectedItem = .dashboard
            }
        }
        .onAppear {
            appState.notificationManager.requestPermission()
        }
    }

    @ViewBuilder
    private func sidebarLabel(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent")
        case .connection:
            Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
        case .goals:
            Label("Goals", systemImage: "target")
        case .history:
            Label("History", systemImage: "clock.arrow.circlepath")
        case .settings:
            Label("Settings", systemImage: "gear")
        }
    }
}
