import Foundation
import Observation

@Observable
class AppState {
    let treadmillState: TreadmillState
    let bleManager: TreadmillBLEManager
    let dataManager: DataManager
    let goalManager: GoalManager
    let workoutStore: WorkoutStore
    let statsCalculator: StatsCalculator
    let workoutRecorder: WorkoutRecorder
    let notificationManager: DeskRunNotificationManager
    var settings: AppSettings

    init() {
        let treadmillState = TreadmillState()
        let dataManager = DataManager()
        let settings = dataManager.loadSettings()
        let workoutStore = WorkoutStore(dataManager: dataManager)
        let goalManager = GoalManager(dataManager: dataManager)
        let statsCalculator = StatsCalculator(workoutStore: workoutStore)

        // Register all known treadmill adapters before creating the BLE manager.
        // Add new adapters here as they are implemented.
        TreadmillAdapterRegistry.shared.register(PitPatAdapter.self)

        self.treadmillState = treadmillState
        self.bleManager = TreadmillBLEManager(state: treadmillState)
        self.dataManager = dataManager
        self.settings = settings
        self.workoutStore = workoutStore
        self.goalManager = goalManager
        self.statsCalculator = statsCalculator
        self.workoutRecorder = WorkoutRecorder(treadmillState: treadmillState, workoutStore: workoutStore)
        self.notificationManager = DeskRunNotificationManager(
            workoutStore: workoutStore,
            goalManager: goalManager,
            statsCalculator: statsCalculator,
            settings: settings
        )

        // Wire up auto-recording
        self.bleManager.onStateUpdate = { [weak workoutRecorder] in
            workoutRecorder?.handleStateUpdate()
        }

        // Request notification permission
        notificationManager.requestPermission()
    }

    func saveSettings() {
        dataManager.saveSettings(settings)
        notificationManager.updateSettings(settings)
    }
}
