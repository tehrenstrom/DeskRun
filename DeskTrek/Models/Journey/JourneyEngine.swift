import AppKit
import Foundation
import Observation

struct ActiveEncounter: Identifiable, Equatable {
    let id = UUID()
    let event: EncounterEvent
    let startedAt: Date

    var deadline: Date {
        startedAt.addingTimeInterval(event.timeoutSeconds)
    }

    static func == (lhs: ActiveEncounter, rhs: ActiveEncounter) -> Bool {
        lhs.id == rhs.id
    }
}

struct LandmarkNotice: Identifiable, Equatable {
    let id = UUID()
    let landmark: Landmark
    let shownAt: Date = Date()
}

@Observable
final class JourneyEngine {
    private let treadmillState: TreadmillState
    private let store: JourneyStore
    private let walkSession: WalkSession?

    private(set) var currentTrail: Trail?

    // Presentation surfaces — views bind to these.
    var pendingEncounter: ActiveEncounter?
    var pendingLandmark: LandmarkNotice?
    var lastResultText: String?
    var showCompletion: Bool = false
    /// A brief flavor caption triggered by ambient wildlife/weather. Purely
    /// visual — no state changes, no input. Auto-dismisses after ~4 s.
    var ambientCaption: String?

    private var pendingEncounterQueue: [EncounterEvent] = []
    private var timeoutTask: Task<Void, Never>?
    private var persistDebounceTask: Task<Void, Never>?
    private var ambientCaptionTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private var lastAmbientCaptionMile: Double = -1  // -1 = no caption yet
    private static let ambientCaptionMileGap: Double = 1.0

    init(treadmillState: TreadmillState, store: JourneyStore, walkSession: WalkSession? = nil) {
        self.treadmillState = treadmillState
        self.store = store
        self.walkSession = walkSession
        if let active = store.active {
            self.currentTrail = TrailCatalog.trail(for: active.trailID)
        }
        registerSleepWakeObserver()
    }

    deinit {
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        timeoutTask?.cancel()
        persistDebounceTask?.cancel()
        ambientCaptionTask?.cancel()
    }

    // MARK: - Ambient captions

    /// Surface a one-line caption from the ambient encounters layer. Rate-limited
    /// to at most one per `ambientCaptionMileGap` miles walked and suppressed
    /// while a narrative encounter or landmark notice is on screen.
    @MainActor
    func showAmbientCaption(_ text: String) {
        guard pendingEncounter == nil, pendingLandmark == nil else { return }
        guard !text.isEmpty else { return }
        if let miles = store.active?.milesTraveled {
            if lastAmbientCaptionMile >= 0 && (miles - lastAmbientCaptionMile) < Self.ambientCaptionMileGap {
                return
            }
            lastAmbientCaptionMile = miles
        }
        ambientCaption = text
        ambientCaptionTask?.cancel()
        ambientCaptionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.ambientCaption == text {
                self.ambientCaption = nil
            }
        }
    }

    @MainActor
    func dismissAmbientCaption() {
        ambientCaption = nil
        ambientCaptionTask?.cancel()
    }

    // MARK: - Lifecycle

    func start(trail: Trail, targetDate: Date?) {
        // Abandon any prior active journey.
        if var existing = store.active {
            existing.status = .abandoned
            store.appendToHistory(existing)
            store.clearActive()
        }
        let baselineKm = treadmillState.distance
        let state = JourneyState(
            trailID: trail.id,
            startedAt: Date(),
            milesTraveled: 0,
            morale: 75,
            energy: 100,
            status: .active,
            targetCompletionDate: targetDate,
            baselineTreadmillKm: baselineKm,
            lastSeenTreadmillKm: baselineKm
        )
        currentTrail = trail
        store.saveActive(state)
    }

    func abandon() {
        guard var state = store.active else { return }
        state.status = .abandoned
        store.appendToHistory(state)
        store.clearActive()
        currentTrail = nil
        pendingEncounter = nil
        pendingLandmark = nil
        pendingEncounterQueue.removeAll()
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    // MARK: - Tick (fires on every BLE update)

    func handleTick() {
        guard var state = store.active, state.status == .active,
              let trail = currentTrail ?? TrailCatalog.trail(for: state.trailID)
        else { return }

        let currentKm = treadmillState.distance
        self.currentTrail = trail

        // Miles only accrue when the current walk is explicitly a journey walk
        // AND the journey is not paused. Free walks (dashboard), device-initiated
        // sessions, and paused journeys all skip accrual — but we still roll the
        // baseline forward so resumed journey walks don't retroactively absorb
        // any of that distance.
        let isJourneyWalk = walkSession?.context == .journey
            && walkSession?.journeyID == state.id
        let accruing = isJourneyWalk && state.isTrackingEnabled
        guard accruing else {
            state.baselineTreadmillKm = currentKm - (state.milesTraveled * 1.60934)
            state.lastSeenTreadmillKm = currentKm
            store.saveActive(state)
            return
        }

        var deltaKm = currentKm - state.lastSeenTreadmillKm
        if deltaKm < 0 {
            // Odometer reset — rebase baseline, no forward progress this tick.
            state.baselineTreadmillKm = currentKm - (state.milesTraveled * 1.60934)
            deltaKm = 0
        }
        let previousMiles = state.milesTraveled
        let deltaMiles = deltaKm * 0.621371
        state.milesTraveled = min(trail.totalMiles, state.milesTraveled + deltaMiles)
        state.lastSeenTreadmillKm = currentKm

        if deltaMiles > 0 {
            emitEvents(in: previousMiles...state.milesTraveled, state: &state, trail: trail)
        }

        store.saveActive(state)

        if state.milesTraveled >= trail.totalMiles {
            completeJourney()
        } else {
            schedulePersist()
        }
    }

    // MARK: - Tracking toggle

    var isTrackingEnabled: Bool {
        store.active?.isTrackingEnabled ?? true
    }

    func setTrackingEnabled(_ enabled: Bool) {
        guard var state = store.active else { return }
        state.isTrackingEnabled = enabled
        // Always refresh the baseline when flipping, so neither direction sneaks in miles.
        state.baselineTreadmillKm = treadmillState.distance - (state.milesTraveled * 1.60934)
        state.lastSeenTreadmillKm = treadmillState.distance
        store.saveActive(state)
    }

    private func emitEvents(in range: ClosedRange<Double>, state: inout JourneyState, trail: Trail) {
        // Landmarks
        for landmark in trail.landmarks where landmark.mileMarker > range.lowerBound && landmark.mileMarker <= range.upperBound {
            if state.visitedLandmarkIDs.insert(landmark.id).inserted {
                pendingLandmark = LandmarkNotice(landmark: landmark)
                // Sound synthesis and portrait persistence are pushed off this
                // tick. They're observable-state writers that landed in the
                // same frame as `pendingLandmark` + `visitedLandmarkIDs` above
                // and triggered a main-thread hang on first-landmark crossing.
                let trailID = trail.id
                let landmarkID = landmark.id
                let journeyID = state.id
                Task { @MainActor [weak self] in
                    SoundManager.shared.playGoalAchieved()
                    self?.store.addPortrait(TrailPortrait(
                        trailID: trailID,
                        landmarkID: landmarkID,
                        journeyID: journeyID
                    ))
                }
            }
        }

        // Encounters — persist fired IDs before showing, to avoid double-fire on crash
        for event in trail.encounters where event.triggerMile > range.lowerBound && event.triggerMile <= range.upperBound {
            guard !state.firedEncounterIDs.contains(event.id) else { continue }
            state.firedEncounterIDs.insert(event.id)
            if pendingEncounter == nil {
                presentEncounter(event)
            } else {
                pendingEncounterQueue.append(event)
            }
        }
    }

    // MARK: - Encounters

    private func presentEncounter(_ event: EncounterEvent) {
        let active = ActiveEncounter(event: event, startedAt: Date())
        pendingEncounter = active
        SoundManager.shared.playWorkoutStarted()
        scheduleTimeout(for: active)
    }

    private func scheduleTimeout(for encounter: ActiveEncounter) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            let nanos = UInt64(encounter.event.timeoutSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            guard let self, let current = self.pendingEncounter, current.id == encounter.id else { return }
            self.resolve(choiceID: current.event.defaultChoiceID, wasDefault: true)
        }
    }

    func resolve(choiceID: String, wasDefault: Bool) {
        guard let active = pendingEncounter,
              let choice = active.event.choices.first(where: { $0.id == choiceID }) ?? active.event.choices.first,
              var state = store.active
        else { return }

        timeoutTask?.cancel()
        timeoutTask = nil

        state.morale = max(0, min(100, state.morale + choice.moraleDelta))
        state.energy = max(0, min(100, state.energy + choice.energyDelta))

        if let badgeID = choice.badgeAwarded {
            state.earnedBadgeIDs.insert(badgeID)
            store.addEarnedBadges([badgeID])
        }

        state.choices.append(JourneyChoice(
            encounterID: active.event.id,
            choiceID: choice.id,
            decidedAt: Date(),
            wasDefault: wasDefault,
            milesAtDecision: state.milesTraveled
        ))

        // Subquest progression
        if let subquestID = active.event.subquestID,
           let trail = currentTrail,
           let subquest = trail.subquests.first(where: { $0.id == subquestID }),
           let stageIndex = subquest.stageEncounterIDs.firstIndex(of: active.event.id) {
            let nextIndex = stageIndex + 1
            state.subquestProgress[subquestID] = nextIndex
            if nextIndex >= subquest.stageEncounterIDs.count,
               let completionBadge = subquest.completionBadgeID {
                state.earnedBadgeIDs.insert(completionBadge)
                store.addEarnedBadges([completionBadge])
            }
        }

        lastResultText = choice.resultText
        store.saveActive(state)

        // Clear and present next in queue if any
        pendingEncounter = nil
        if let next = pendingEncounterQueue.first {
            pendingEncounterQueue.removeFirst()
            presentEncounter(next)
        }
    }

    func dismissLandmarkNotice() {
        pendingLandmark = nil
    }

    func dismissResultText() {
        lastResultText = nil
    }

    // MARK: - Completion

    private func completeJourney() {
        guard var state = store.active, let trail = currentTrail else { return }
        state.status = .completed
        state.completedAt = Date()
        let totalDays = max(1, Calendar.current.dateComponents([.day], from: state.startedAt, to: state.completedAt ?? Date()).day ?? 1)
        let certificate = Certificate(
            trailID: trail.id,
            journeyID: state.id,
            completedAt: state.completedAt ?? Date(),
            totalMiles: trail.totalMiles,
            totalDays: totalDays,
            finalMorale: state.morale,
            earnedBadgeIDs: Array(state.earnedBadgeIDs)
        )
        store.appendTrophy(certificate)
        store.appendToHistory(state)
        store.clearActive()
        currentTrail = nil
        pendingEncounter = nil
        pendingEncounterQueue.removeAll()
        showCompletion = true
        SoundManager.shared.playGoalAchieved()
    }

    // MARK: - Persistence debounce

    private func schedulePersist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            guard let self, let active = self.store.active else { return }
            self.store.saveActive(active)
        }
    }

    // MARK: - Sleep / wake

    private func registerSleepWakeObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    private func handleWake() {
        guard let active = pendingEncounter else { return }
        if Date() >= active.deadline {
            resolve(choiceID: active.event.defaultChoiceID, wasDefault: true)
        }
    }

#if DEBUG
    /// Push the active journey's odometer just past the next landmark and
    /// fire the event pipeline, so landmark-crossing bugs can be reproduced
    /// without walking the real distance. Treadmill baselines are rebased
    /// so subsequent real BLE ticks don't double-count the jump.
    func debugAdvanceToNextLandmark() {
        guard var state = store.active, state.status == .active,
              let trail = currentTrail ?? TrailCatalog.trail(for: state.trailID),
              let next = trail.landmarks
                .filter({ $0.mileMarker > state.milesTraveled })
                .min(by: { $0.mileMarker < $1.mileMarker })
        else { return }

        self.currentTrail = trail

        // Teleport silently to just before the landmark — pre-mark any
        // encounters we're skipping as already-fired so only the landmark
        // event actually surfaces. This isolates landmark-crossing bugs
        // from encounter-overlay bugs.
        let silentEnd = max(state.milesTraveled, next.mileMarker - 0.001)
        for event in trail.encounters where event.triggerMile <= silentEnd {
            state.firedEncounterIDs.insert(event.id)
        }
        state.milesTraveled = silentEnd

        // Now emit over a tiny range that only contains the landmark itself.
        let previousMiles = state.milesTraveled
        state.milesTraveled = min(trail.totalMiles, next.mileMarker + 0.01)
        state.baselineTreadmillKm = treadmillState.distance - (state.milesTraveled * 1.60934)
        state.lastSeenTreadmillKm = treadmillState.distance

        emitEvents(in: previousMiles...state.milesTraveled, state: &state, trail: trail)

        if state.milesTraveled >= trail.totalMiles {
            store.saveActive(state)
            completeJourney()
        } else {
            store.saveActive(state)
        }
    }
#endif
}
