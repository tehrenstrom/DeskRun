import CoreGraphics
import Foundation

// MARK: - Model

/// One entry on a signpost plank — a named landmark and how far it lies ahead.
struct SignWaypoint: Hashable {
    let name: String
    let milesAway: Double
}

/// An immutable trail signpost placed in the world. Position and contents are
/// a pure function of `(trail, slotIndex)`; same trail always produces the
/// same signs in the same places.
struct TrailSignpost: Identifiable, Hashable {
    let id: Int
    let spawnMile: Double
    let waypoints: [SignWaypoint]
}

/// Per-frame render info for an alive signpost, in the enclosing view's
/// screen-space coordinates.
struct TrailSignpostRender: Identifiable {
    let id: Int
    let sign: TrailSignpost
    let x: CGFloat
    let footY: CGFloat
    let opacity: Double
}

// MARK: - Scheduler

/// Pure, deterministic signpost placement + content generation. Mirrors the
/// scroll-world math from `AmbientScheduler` so signs move with the trail in
/// lock-step with landmarks and foreground wildlife.
enum TrailSignpostScheduler {

    /// Roughly one signpost every `spacingMiles` miles, jittered ±`jitterMiles`
    /// per slot via the seeded RNG so spacing feels natural rather than metronomic.
    private static let spacingMiles: Double = 20.0
    private static let jitterMiles: Double = 2.0

    /// World-space window around the hiker where a sign is considered alive.
    /// Matches the foreground-ambient scroll-motion window so fades line up.
    private static let aheadMiles: Double = 0.9
    private static let behindMiles: Double = 0.35

    /// Cap on plank count per sign.
    private static let maxWaypoints: Int = 3

    /// Don't show a sign whose nearest upcoming landmark is further than this —
    /// reads as absurd on a real trailhead ("MT WHITNEY 198mi").
    private static let waypointCutoffMiles: Double = 120.0

    /// A sign needs at least this many upcoming landmarks to be worth rendering.
    private static let minWaypoints: Int = 2

    /// Pass-by fade: signs disappear inside this dead-zone around the hiker so
    /// the wooden post doesn't awkwardly overlap the hiker sprite.
    private static let passByDeadZone: CGFloat = 60

    static func activeSigns(
        trail: Trail,
        milesTraveled: Double,
        hikerScreenX: CGFloat,
        pxPerMile: CGFloat,
        bandBottomY: CGFloat,
        bandWidth: CGFloat
    ) -> [TrailSignpostRender] {

        let currentSlot = Int(floor(milesTraveled / spacingMiles))
        // Window of slots that might have a sign currently on screen. Two on
        // each side is plenty given the spacing vs. alive-window geometry.
        let startSlot = max(0, currentSlot - 2)
        let endSlot = currentSlot + 2

        var results: [TrailSignpostRender] = []

        for slot in startSlot...endSlot {
            guard let sign = signpost(for: slot, trail: trail) else { continue }

            let worldOffsetMiles = sign.spawnMile - milesTraveled
            if worldOffsetMiles < -behindMiles { continue }
            if worldOffsetMiles > aheadMiles { continue }

            let screenX = hikerScreenX + CGFloat(worldOffsetMiles) * pxPerMile
            // Cull if fully offscreen either side.
            if screenX < -120 || screenX > bandWidth + 120 { continue }

            let fadeIn = smoothstep(Double((aheadMiles - worldOffsetMiles) / 0.25).clamped(to: 0...1))
            let fadeOut = smoothstep(Double((worldOffsetMiles + behindMiles) / 0.15).clamped(to: 0...1))
            let passBy: Double = {
                let distance = abs(screenX - hikerScreenX)
                if distance < passByDeadZone {
                    return smoothstep(Double(distance / passByDeadZone))
                }
                return 1.0
            }()
            let opacity = min(fadeIn, fadeOut) * passBy
            if opacity < 0.01 { continue }

            results.append(
                TrailSignpostRender(
                    id: sign.id,
                    sign: sign,
                    x: screenX,
                    footY: bandBottomY,
                    opacity: opacity
                )
            )
        }
        return results
    }

    // MARK: - Slot → signpost

    /// Build the signpost for a given slot index, or nil if this slot produces
    /// no sign (past trail end, or not enough upcoming landmarks to be useful).
    private static func signpost(for slot: Int, trail: Trail) -> TrailSignpost? {
        var rng = SeededRNG(seed: hashSeed(trailID: trail.id, slot: slot))
        let jitter = rng.nextDouble(in: -jitterMiles...jitterMiles)
        let spawnMile = Double(slot) * spacingMiles + jitter

        // Slot zero (around mile 0 ± jitter) would clash with the trailhead
        // landmark; skip it — the start-of-trail moment is already its own beat.
        if spawnMile < 5.0 { return nil }
        if spawnMile > trail.totalMiles - 1.0 { return nil }

        let upcoming = trail.landmarks
            .filter { $0.mileMarker > spawnMile && $0.mileMarker - spawnMile <= waypointCutoffMiles }
            .sorted { $0.mileMarker < $1.mileMarker }
            .prefix(maxWaypoints)

        guard upcoming.count >= minWaypoints else { return nil }

        let waypoints = upcoming.map {
            SignWaypoint(name: $0.name, milesAway: $0.mileMarker - spawnMile)
        }

        return TrailSignpost(
            id: hashSeed(trailID: trail.id, slot: slot),
            spawnMile: spawnMile,
            waypoints: waypoints
        )
    }

    // MARK: - Helpers

    private static func smoothstep(_ t: Double) -> Double {
        let x = t.clamped(to: 0...1)
        return x * x * (3 - 2 * x)
    }

    /// FNV-1a hash over ("signpost:" + trailID + slot). Namespaced so signpost
    /// slots never collide with ambient-encounter slots.
    private static func hashSeed(trailID: String, slot: Int) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in "signpost:".utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        for b in trailID.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        h ^= UInt64(bitPattern: Int64(slot))
        h = h &* 0x100000001b3
        return Int(truncatingIfNeeded: h)
    }
}

// MARK: - Seeded RNG (copy of the one in AmbientEncounters — kept local to
// avoid making that type public)

private struct SeededRNG {
    private var state: UInt64
    init(seed: Int) {
        self.state = UInt64(bitPattern: Int64(seed)) &+ 0x9e3779b97f4a7c15
        if state == 0 { state = 0x9e3779b97f4a7c15 }
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let r = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + r * (range.upperBound - range.lowerBound)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
