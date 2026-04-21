import Foundation
import Observation

@Observable
class WorkoutRecorder {
    private let treadmillState: TreadmillState
    private let workoutStore: WorkoutStore
    private let journeyStore: JourneyStore?
    private let walkSession: WalkSession?
    var goalManager: GoalManager?
    var settings: AppSettings?

    var isRecording: Bool = false
    var showSavedToast: Bool = false

    private var currentWorkoutStart: Date?
    private var lastNonZeroSpeed: Date?
    private var zeroSpeedTimer: Timer?
    private(set) var sessionDistance: Double = 0
    private(set) var sessionCalories: Int = 0
    private(set) var sessionDuration: TimeInterval = 0
    private var lastObservedDistance: Double?
    private var lastObservedCalories: Int?
    private var lastObservedDuration: TimeInterval?
    private var lastAccumulateAt: Date?
    private var lastConnectionStatus: ConnectionStatus = .disconnected

    private static let stopDelay: TimeInterval = 30  // seconds of zero speed before auto-stop
    private static let minimumActiveSpeed = 0.05

    init(
        treadmillState: TreadmillState,
        workoutStore: WorkoutStore,
        journeyStore: JourneyStore? = nil,
        walkSession: WalkSession? = nil
    ) {
        self.treadmillState = treadmillState
        self.workoutStore = workoutStore
        self.journeyStore = journeyStore
        self.walkSession = walkSession
    }

    /// Call this on every BLE state update
    func handleStateUpdate() {
        // On reconnect (and on first connect), treat this tick as a fresh
        // observation: the treadmill may have reset its odometer to zero, or
        // replayed its remembered distance, or both. Either way we can't
        // trust the delta across the disconnect — rebase from the current
        // values without accumulating anything this tick.
        let currentStatus = treadmillState.connectionStatus
        if lastConnectionStatus != .connected && currentStatus == .connected && isRecording {
            rebaseObservations()
        }
        lastConnectionStatus = currentStatus

        let sessionAdvanced = isRecording ? accumulateSessionMetrics() : false
        let hasActivitySignal = treadmillState.isRunning
            || treadmillState.currentSpeed > Self.minimumActiveSpeed
            || sessionAdvanced

        if hasActivitySignal {
            lastNonZeroSpeed = Date()
            zeroSpeedTimer?.invalidate()
            zeroSpeedTimer = nil

            if !isRecording {
                startRecording()
            }
        } else if isRecording {
            // Speed is zero while recording — start countdown
            if zeroSpeedTimer == nil {
                zeroSpeedTimer = Timer.scheduledTimer(withTimeInterval: Self.stopDelay, repeats: false) { [weak self] _ in
                    self?.stopRecording()
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        currentWorkoutStart = Date()
        lastNonZeroSpeed = currentWorkoutStart
        sessionDistance = 0
        sessionCalories = 0
        sessionDuration = 0
        rebaseObservations()
        SoundManager.shared.playWorkoutStarted()
        print("🏃 Workout recording started")
    }

    /// Snapshot the current treadmill counters as the baseline so the next
    /// `accumulateSessionMetrics` call emits zero deltas. Used at session
    /// start and after a BLE reconnect (where the treadmill may have reset
    /// or replayed values we'd otherwise double-count).
    private func rebaseObservations() {
        lastObservedDistance = treadmillState.distance
        lastObservedCalories = treadmillState.calories
        lastObservedDuration = treadmillState.duration
        lastAccumulateAt = Date()
    }

    func stopRecording() {
        guard isRecording, let startDate = currentWorkoutStart else { return }

        _ = accumulateSessionMetrics()

        zeroSpeedTimer?.invalidate()
        zeroSpeedTimer = nil
        let endDate = lastNonZeroSpeed ?? Date()
        let fallbackDuration = max(0, endDate.timeIntervalSince(startDate))
        let recordedDuration = max(sessionDuration, fallbackDuration)

        // Final safety clamp: if the distance/duration ratio still implies a
        // physically impossible speed, cap distance to what the duration can
        // plausibly cover. This guards against BLE firmware quirks that slip
        // past the per-tick checks.
        var recordedDistance = sessionDistance
        var recordedSpeed: Double = 0
        if recordedDuration > 0 {
            let rawSpeed = sessionDistance / (recordedDuration / 3600)
            if rawSpeed > WorkoutSanity.maxPlausibleSpeedKmh {
                recordedDistance = WorkoutSanity.maxPlausibleSpeedKmh * (recordedDuration / 3600)
                recordedSpeed = WorkoutSanity.maxPlausibleSpeedKmh
                print("⚠️ Clamped workout speed from \(String(format: "%.1f", rawSpeed)) km/h to cap (\(WorkoutSanity.maxPlausibleSpeedKmh) km/h)")
            } else {
                recordedSpeed = rawSpeed
            }
        }

        let workout = WorkoutRecord(
            startDate: startDate,
            endDate: endDate,
            distance: recordedDistance,
            steps: StepsEstimate.steps(fromKm: recordedDistance),
            calories: sessionCalories,
            duration: recordedDuration,
            averageSpeed: recordedSpeed,
            journeyID: activeJourneyID
        )

        // Only save if meaningful (at least 1 minute or 0.01 km)
        if workout.duration >= 60 || workout.distance >= 0.01 {
            workoutStore.addWorkout(workout)
            SoundManager.shared.playWorkoutEnded()
            print("💾 Workout saved: \(workout.formattedDistance) in \(workout.formattedDuration)")

            // Check if daily goal was just hit
            if let gm = goalManager, let s = settings {
                gm.checkGoalAchievement(workouts: workoutStore.todaysWorkouts, settings: s)
            }

            // Show toast
            showSavedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.showSavedToast = false
            }
        }

        isRecording = false
        currentWorkoutStart = nil
        lastNonZeroSpeed = nil
        sessionDistance = 0
        sessionCalories = 0
        sessionDuration = 0
        lastObservedDistance = nil
        lastObservedCalories = nil
        lastObservedDuration = nil
        lastAccumulateAt = nil

        // Clear walk context so the next auto-start defaults to a free walk.
        walkSession?.markFreeWalk()
    }

    /// A workout is attributed to the active journey only when the walk was
    /// intentionally started as a journey walk (via `JourneyWalkCard`) AND that
    /// journey is still active. Free walks and device-initiated sessions fall
    /// through to `nil`.
    private var activeJourneyID: UUID? {
        guard
            let session = walkSession,
            session.context == .journey,
            let sessionJourneyID = session.journeyID,
            let active = journeyStore?.active,
            active.id == sessionJourneyID
        else {
            return nil
        }
        return active.id
    }

    @discardableResult
    private func accumulateSessionMetrics() -> Bool {
        var advanced = false
        let now = Date()
        let wallDelta = lastAccumulateAt.map { now.timeIntervalSince($0) } ?? 0
        lastAccumulateAt = now

        // Duration first — it's the denominator we use to sanity-check distance.
        // Reject negative deltas (odometer reset) and implausibly large jumps
        // that exceed the wall-clock gap (+2s slack for BLE jitter).
        var acceptedDurationDelta: TimeInterval = 0
        if let lastObservedDuration {
            let raw = treadmillState.duration - lastObservedDuration
            if raw > 0 && (wallDelta <= 0 || raw <= wallDelta + 2.0) {
                acceptedDurationDelta = raw
                sessionDuration += raw
                advanced = advanced || raw > 0
            }
        }
        lastObservedDuration = treadmillState.duration

        // Distance — only accept positive deltas, and cap at the physical
        // maximum given the time elapsed. This is what saves us from the
        // "BLE replayed the odometer" class of bug where a reconnect slips
        // an enormous distance delta through without any duration delta.
        if let lastObservedDistance {
            let raw = treadmillState.distance - lastObservedDistance
            if raw > 0 {
                let referenceSeconds = max(acceptedDurationDelta, wallDelta)
                let cap = WorkoutSanity.maxPlausibleSpeedKmh * (referenceSeconds / 3600.0)
                let accepted = referenceSeconds > 0 ? min(raw, cap) : 0
                if accepted > 0 {
                    sessionDistance += accepted
                    advanced = advanced || accepted > 0.0001
                }
            }
        }
        lastObservedDistance = treadmillState.distance

        if let lastObservedCalories {
            let calorieDelta = treadmillState.calories - lastObservedCalories
            if calorieDelta > 0 {
                sessionCalories += calorieDelta
                advanced = advanced || calorieDelta > 0
            }
        }
        lastObservedCalories = treadmillState.calories

        return advanced
    }
}
