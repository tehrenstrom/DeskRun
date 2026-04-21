import Foundation

enum LegacyJourneyMigration {
    /// Move any legacy "journey preset" goals (AT, PCT, Camino, etc.) into the
    /// archive file. We do not auto-convert them into JourneyState — those goals
    /// are distance targets, not sessions, and silent conversion would misrepresent miles.
    static func run(goalManager: GoalManager, journeyStore: JourneyStore) {
        let matches = goalManager.goals.filter { goal in
            goal.timeframe == .custom && LegacyJourneyPresetNames.all.contains(goal.name)
        }
        guard !matches.isEmpty else { return }

        journeyStore.appendArchivedGoals(matches)
        for goal in matches {
            goalManager.deleteGoal(id: goal.id)
        }
    }
}

/// Seed Trail Portraits for landmarks visited before the portrait feature existed.
/// Runs once. Safe to re-run because `JourneyStore.addPortrait` dedupes by
/// `(trailID, landmarkID)`. Uses the journey's `startedAt` as the collected
/// timestamp — we don't know the exact pass-by moment, but "sometime during
/// the journey" is a reasonable anchor.
enum PortraitBackfillMigration {
    static func run(journeyStore: JourneyStore) {
        let allJourneys = ([journeyStore.active].compactMap { $0 } + journeyStore.history)
        var seeded = 0
        for journey in allJourneys {
            guard let trail = TrailCatalog.trail(for: journey.trailID) else { continue }
            for landmark in trail.landmarks where journey.visitedLandmarkIDs.contains(landmark.id) {
                let before = journeyStore.portraits.count
                journeyStore.addPortrait(TrailPortrait(
                    trailID: journey.trailID,
                    landmarkID: landmark.id,
                    collectedAt: journey.startedAt,
                    journeyID: journey.id
                ))
                if journeyStore.portraits.count > before { seeded += 1 }
            }
        }
        if seeded > 0 {
            print("🖼  Backfilled \(seeded) trail portrait(s) from already-visited landmarks")
        }
    }
}

/// Scrubs workouts with impossible-speed data. Runs once on app launch.
///
/// Two bad shapes exist in the wild:
///   1. Records synthesized by `JourneyWorkoutBackfillMigration` with real
///      distance and `duration == 0` — these turn the dashboard's aggregate
///      average-speed into absurd values (> 100 mph) because the numerator
///      has their distance but the denominator doesn't have their time.
///   2. Legitimately-recorded records whose distance/duration ratio implies
///      a walking speed above the physical cap (BLE replay, odometer glitch).
///
/// For (1) we keep the distance and invent a duration consistent with a
/// slow-walk pace so the record still contributes honestly to totals.
/// For (2) we clamp distance down to what the duration can plausibly cover.
enum WorkoutSpeedSanitizationMigration {
    /// Pace at which we "amortize" distance-only backfill records — about
    /// 2.5 mph, the app's default walking speed.
    private static let backfillPaceKmh: Double = 4.0

    static func run(workoutStore: WorkoutStore) {
        var updated = workoutStore.workouts
        var fixed = 0

        for i in updated.indices {
            let w = updated[i]

            if w.duration == 0 && w.distance > 0 {
                // Zero-duration record with real distance (backfill artifact).
                // Give it a duration matching a reasonable walking pace and
                // record that pace as its averageSpeed.
                let duration = (w.distance / Self.backfillPaceKmh) * 3600
                updated[i].duration = duration
                updated[i].averageSpeed = Self.backfillPaceKmh
                // Nudge endDate forward so the record's timeline is self-
                // consistent. We don't know the real end, but the anchor date
                // plus the synthesized duration is better than endDate == startDate.
                updated[i].endDate = w.endDate.addingTimeInterval(duration)
                fixed += 1
                continue
            }

            if w.duration > 0 {
                let impliedSpeed = w.distance / (w.duration / 3600)
                if impliedSpeed > WorkoutSanity.maxPlausibleSpeedKmh {
                    updated[i].distance = WorkoutSanity.maxPlausibleSpeedKmh * (w.duration / 3600)
                    updated[i].averageSpeed = WorkoutSanity.maxPlausibleSpeedKmh
                    fixed += 1
                } else if abs(w.averageSpeed - impliedSpeed) > 0.05 {
                    // averageSpeed stored on the record doesn't match what
                    // distance/duration imply — re-derive it so per-record
                    // sanity checks elsewhere stay honest.
                    updated[i].averageSpeed = impliedSpeed
                    fixed += 1
                }
            }
        }

        guard fixed > 0 else { return }
        workoutStore.replaceWorkouts(updated)
        print("🧼 Sanitized \(fixed) workout record(s) with implausible speed data")
    }
}

enum JourneyWorkoutBackfillMigration {
    private static let distanceToleranceKm = 0.05

    static func run(workoutStore: WorkoutStore, journeyStore: JourneyStore) {
        let journeys = ([journeyStore.active].compactMap { $0 } + journeyStore.history)
            .filter { $0.isTrackingEnabled && $0.milesTraveled > 0 }

        guard !journeys.isEmpty else { return }

        var workouts = workoutStore.workouts
        let now = Date()
        var didChange = false

        for journey in journeys {
            let journeyDistanceKm = journey.milesTraveled * 1.60934
            let journeyEnd = journey.completedAt ?? now

            let relatedIndices = workouts.indices.filter { index in
                let workout = workouts[index]
                if workout.journeyID == journey.id {
                    return true
                }
                return workout.endDate >= journey.startedAt && workout.startDate <= journeyEnd
            }

            guard !relatedIndices.isEmpty else { continue }

            for index in relatedIndices where workouts[index].journeyID == nil {
                workouts[index].journeyID = journey.id
                didChange = true
            }

            // Steps are derived from distance at load time (see
            // `WorkoutStore.backfillLegacyStepsIfNeeded`), so `steps == 0` is
            // no longer a reliable "ghost record" signal — detect on the
            // remaining zeroed fields only.
            let suspiciousIndices = relatedIndices.filter { index in
                let workout = workouts[index]
                return workout.distance > 0
                    && workout.duration == 0
                    && workout.averageSpeed == 0
                    && workout.calories == 0
            }

            guard !suspiciousIndices.isEmpty else { continue }

            let recordedDistanceKm = relatedIndices.reduce(0.0) { partial, index in
                partial + workouts[index].distance
            }
            let missingDistanceKm = journeyDistanceKm - recordedDistanceKm

            guard missingDistanceKm > distanceToleranceKm else { continue }

            // Any synthesized duration here should match a reasonable walking
            // pace so the aggregate average-speed math downstream stays sane.
            let paceKmh: Double = 4.0
            let synthesizedDuration = (missingDistanceKm / paceKmh) * 3600

            if suspiciousIndices.count == 1 {
                let index = suspiciousIndices[0]
                workouts[index].distance += missingDistanceKm
                workouts[index].duration += synthesizedDuration
                workouts[index].endDate = workouts[index].endDate.addingTimeInterval(synthesizedDuration)
                workouts[index].averageSpeed = workouts[index].duration > 0
                    ? workouts[index].distance / (workouts[index].duration / 3600)
                    : 0
                didChange = true
                print("🧰 Backfilled journey workout distance by \(String(format: "%.2f", missingDistanceKm)) km for journey \(journey.id)")
                continue
            }

            let anchorDate = suspiciousIndices
                .map { workouts[$0].endDate }
                .max() ?? journeyEnd
            let recoveredWorkout = WorkoutRecord(
                startDate: anchorDate,
                endDate: anchorDate.addingTimeInterval(synthesizedDuration),
                distance: missingDistanceKm,
                steps: StepsEstimate.steps(fromKm: missingDistanceKm),
                calories: 0,
                duration: synthesizedDuration,
                averageSpeed: paceKmh,
                journeyID: journey.id
            )
            workouts.append(recoveredWorkout)
            didChange = true
            print("🧰 Added recovered workout with \(String(format: "%.2f", missingDistanceKm)) km for journey \(journey.id)")
        }

        guard didChange else { return }
        workoutStore.replaceWorkouts(workouts)
    }
}
