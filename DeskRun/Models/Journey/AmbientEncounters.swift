import CoreGraphics
import Foundation

// MARK: - Species

enum AmbientSpecies: String, CaseIterable {
    case cloudSmall
    case cloudLarge
    case bird
    case birdFlock
    case eagle
    case raven
    case marmot
    case deer
    case squirrel
    case hiker
    case butterfly
    case pika
    case bear
    case rain
    case snow

    /// Looks up the sprite registry key for the given animation frame (mod).
    func assetKey(frame: Int) -> String {
        switch self {
        case .cloudSmall:  return "ambient.cloud.small"
        case .cloudLarge:  return "ambient.cloud.large"
        case .bird:        return "ambient.bird.flap.\(frame % 2)"
        case .birdFlock:   return "ambient.bird.flock"
        case .eagle:       return "ambient.eagle.glide"
        case .raven:       return "ambient.raven"
        case .marmot:      return "ambient.marmot.sit"
        case .deer:        return "ambient.deer.stand"
        case .squirrel:    return "ambient.squirrel.run.\(frame % 2)"
        case .hiker:       return "ambient.hiker.distant.\(frame % 2)"
        case .butterfly:   return "ambient.butterfly.\(frame % 2)"
        case .pika:        return "ambient.pika"
        case .bear:        return "ambient.bear.distant"
        case .rain:        return "ambient.rain.sheet"
        case .snow:        return "ambient.snow.sheet"
        }
    }

    /// Height of the sprite on screen (pt). Width derived from aspect ratio.
    var displayHeight: CGFloat {
        switch self {
        case .cloudSmall:  return 18
        case .cloudLarge:  return 28
        case .bird:        return 10
        case .birdFlock:   return 14
        case .eagle:       return 12
        case .raven:       return 14
        case .marmot:      return 22
        case .deer:        return 38
        case .squirrel:    return 18
        case .hiker:       return 36
        case .butterfly:   return 14
        case .pika:        return 16
        case .bear:        return 34
        case .rain, .snow: return 120
        }
    }

    /// Sprite width:height ratio for converting displayHeight → displayWidth.
    var aspectRatio: CGFloat {
        switch self {
        case .cloudSmall:  return 32.0 / 12.0
        case .cloudLarge:  return 56.0 / 18.0
        case .bird:        return 12.0 / 6.0
        case .birdFlock:   return 26.0 / 8.0
        case .eagle:       return 20.0 / 6.0
        case .raven:       return 14.0 / 8.0
        case .marmot:      return 16.0 / 12.0
        case .deer:        return 22.0 / 18.0
        case .squirrel:    return 12.0 / 10.0
        case .hiker:       return 10.0 / 14.0
        case .butterfly:   return 10.0 / 8.0
        case .pika:        return 10.0 / 8.0
        case .bear:        return 26.0 / 16.0
        case .rain, .snow: return 48.0 / 32.0
        }
    }

    /// Frame period in seconds (for two-frame animations).
    var framePeriod: Double {
        switch self {
        case .bird:      return 0.18
        case .squirrel:  return 0.08
        case .hiker:     return 0.32
        case .butterfly: return 0.22
        default:         return 1.0
        }
    }

    /// Species that merit a brief flavor caption when they appear.
    var isNotable: Bool {
        switch self {
        case .bear, .eagle, .marmot, .hiker, .deer, .raven, .butterfly: return true
        default: return false
        }
    }

    /// Flavor caption shown in the ambient-caption toast.
    var caption: String {
        switch self {
        case .bear:      return "A bear moves through the trees in the distance."
        case .eagle:     return "An eagle circles overhead."
        case .marmot:    return "A marmot watches you from a sun-warm boulder."
        case .hiker:     return "A fellow hiker nods as they pass."
        case .deer:      return "A deer looks up from grazing, then returns to its meal."
        case .raven:     return "A raven calls from the cliffs."
        case .butterfly: return "A butterfly drifts across the wildflowers."
        default:         return ""
        }
    }
}

// MARK: - Layers & Motion

enum AmbientZLayer: String, CaseIterable {
    case sky        // clouds, birds, eagles, weather
    case distance   // distant hikers, bears, ravens
    case foreground // marmots, deer, squirrels, butterflies, pikas, close-up hikers
}

enum AmbientMotion {
    /// Time-based horizontal drift. `speed` in pt/sec, positive = rightward.
    case drift(speed: CGFloat)
    /// Anchored to world space — moves with trail scroll (same formula as landmarks).
    case scroll
    /// One-shot horizontal dart across the trail.
    case cross(durationSec: Double, direction: CGFloat)
    /// Sinusoidal flapping/gliding path across the sky.
    case flap(speed: CGFloat, amplitude: CGFloat, wavelengthSec: Double)
    /// Full-width static weather sheet, very slow drift.
    case sheet(speed: CGFloat)
}

// MARK: - Actor

/// An immutable description of a single ambient spawn. Position/opacity is
/// derived by `AmbientScheduler.render(_:context:)` as a pure function of
/// `(milesTraveled, date)`.
struct AmbientActor: Identifiable {
    let id: Int
    let species: AmbientSpecies
    let band: AmbientZLayer
    let motion: AmbientMotion
    let spawnMile: Double
    let spawnDate: Date
    /// Row within the band, 0.0 (top) → 1.0 (bottom).
    let rowFraction: CGFloat
    /// Initial X position (pt) for time-based motion kernels; unused for `.scroll`.
    let initialX: CGFloat
    /// Visual size multiplier (0.8–1.2 for natural variety).
    let sizeScale: CGFloat
    /// Horizontal flip for variety.
    let flipH: Bool
}

/// Computed render info for an alive actor on a given frame.
struct AmbientRender: Identifiable {
    let id: Int
    let species: AmbientSpecies
    let assetKey: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let opacity: Double
    let flipH: Bool
}

// MARK: - Layout context

struct AmbientLayoutContext {
    let bandWidth: CGFloat
    let bandHeight: CGFloat
    /// Top-left Y of this band in the enclosing ZStack.
    let bandOriginY: CGFloat
    /// Hiker's screen X (for scroll-based actors).
    let hikerScreenX: CGFloat
    /// Pixels per world-mile (matches landmarks formula).
    let pxPerMile: CGFloat
}

// MARK: - Pool (trail-aware species selection)

enum AmbientPool {
    /// Returns the weighted species list for a given trail + mile + band.
    /// Uses JMT-tuned biome zones for trail id `"jmt"`; any other trail gets
    /// the generic safe-for-any-biome pool.
    static func species(trailID: String, mile: Double, band: AmbientZLayer) -> [AmbientSpecies] {
        if trailID == "jmt" {
            return jmt(mile: mile, band: band)
        }
        return generic(band: band)
    }

    private static func jmt(mile: Double, band: AmbientZLayer) -> [AmbientSpecies] {
        switch (band, mile) {
        // 0..<40 — Yosemite valley / high country ascent: forest, meadows
        case (.sky, 0..<40):
            return [.cloudSmall, .cloudSmall, .cloudLarge, .bird, .bird, .birdFlock]
        case (.distance, 0..<40):
            return [.hiker, .hiker, .raven]
        case (.foreground, 0..<40):
            return [.deer, .squirrel, .squirrel, .butterfly, .butterfly, .hiker]

        // 40..<80 — High Sierra: marmots, occasional bear
        case (.sky, 40..<80):
            return [.cloudSmall, .cloudLarge, .bird, .birdFlock, .eagle]
        case (.distance, 40..<80):
            return [.hiker, .hiker, .bear, .raven]
        case (.foreground, 40..<80):
            return [.marmot, .marmot, .squirrel, .deer, .hiker, .butterfly]

        // 80..<130 — Alpine / Evolution Basin: sparser life, more weather
        case (.sky, 80..<130):
            return [.cloudSmall, .cloudLarge, .cloudLarge, .eagle, .raven, .rain]
        case (.distance, 80..<130):
            return [.hiker, .raven, .raven]
        case (.foreground, 80..<130):
            return [.marmot, .pika, .pika, .hiker]

        // 130+ — Summit approach: solitary, cold, raven/eagle
        case (.sky, _):
            return [.cloudLarge, .cloudLarge, .eagle, .raven, .snow]
        case (.distance, _):
            return [.hiker, .raven]
        case (.foreground, _):
            return [.pika, .raven, .hiker]
        }
    }

    private static func generic(band: AmbientZLayer) -> [AmbientSpecies] {
        switch band {
        case .sky:        return [.cloudSmall, .cloudSmall, .cloudLarge, .bird, .birdFlock]
        case .distance:   return [.hiker, .raven]
        case .foreground: return [.deer, .squirrel, .hiker, .butterfly]
        }
    }
}

// MARK: - Scheduler

/// Pure, deterministic ambient-spawn math. Given `(milesTraveled, speedKmh,
/// date, trailID)` it returns the set of currently-alive actors and their
/// screen positions. Same input → same output (no flicker across frames).
enum AmbientScheduler {

    /// How often new actors spawn, in world-miles, for each band. Actual spawn
    /// interval also jitters per index by ±25% via the seeded RNG.
    private static func baseSpawnIntervalMiles(_ band: AmbientZLayer) -> Double {
        switch band {
        case .sky:        return 0.22
        case .distance:   return 0.80
        case .foreground: return 0.45
        }
    }

    /// How many recent spawn indices to consider (older ones are guaranteed dead).
    private static func liveWindow(_ band: AmbientZLayer) -> Int {
        switch band {
        case .sky:        return 5
        case .distance:   return 3
        case .foreground: return 4
        }
    }

    /// Maximum concurrent actors allowed per band.
    private static func maxConcurrent(_ band: AmbientZLayer) -> Int {
        switch band {
        case .sky:        return 6
        case .distance:   return 3
        case .foreground: return 5
        }
    }

    /// Minimum speed that counts as "actively walking". Below this the
    /// scheduler stops spawning (existing actors continue their exit).
    private static let idleSpeedKmh = 0.1

    /// Main entry point. Returns the list of alive actors rendered at current
    /// milesTraveled + date.
    static func activeActors(
        trailID: String,
        milesTraveled: Double,
        speedKmh: Double,
        isTrackingEnabled: Bool,
        date: Date,
        band: AmbientZLayer,
        context: AmbientLayoutContext
    ) -> [AmbientRender] {

        let spawnInterval = baseSpawnIntervalMiles(band)
        let window = liveWindow(band)
        let maxAlive = maxConcurrent(band)
        let canSpawn = isTrackingEnabled && speedKmh > idleSpeedKmh

        let pool = AmbientPool.species(trailID: trailID, mile: milesTraveled, band: band)
        guard !pool.isEmpty else { return [] }

        let currentIndex = Int(floor(milesTraveled / spawnInterval))
        var results: [AmbientRender] = []

        let startIndex = max(0, currentIndex - window)
        // Don't spawn anything scheduled for the future.
        let endIndex = currentIndex

        for i in startIndex...endIndex {
            // Gate the newest spawn on actively walking (older actors remain
            // visible even if the user just paused — they drift out naturally).
            if i == currentIndex && !canSpawn { continue }

            let actor = makeActor(
                index: i,
                band: band,
                trailID: trailID,
                pool: pool,
                spawnInterval: spawnInterval,
                milesTraveled: milesTraveled,
                date: date,
                context: context
            )

            guard let render = render(actor: actor, milesTraveled: milesTraveled, date: date, context: context) else { continue }
            results.append(render)
        }

        // Enforce concurrent cap — keep newest.
        if results.count > maxAlive {
            results = Array(results.suffix(maxAlive))
        }
        return results
    }

    /// Checks whether the newest-index actor has just spawned this frame
    /// (within a small miles epsilon) and is notable. Used by the view layer
    /// to trigger a flavor caption once per actor.
    static func newlySpawnedNotable(
        trailID: String,
        milesTraveled: Double,
        previousMilesTraveled: Double,
        speedKmh: Double,
        isTrackingEnabled: Bool,
        date: Date,
        band: AmbientZLayer,
        context: AmbientLayoutContext
    ) -> AmbientActor? {
        guard isTrackingEnabled, speedKmh > idleSpeedKmh else { return nil }
        let spawnInterval = baseSpawnIntervalMiles(band)
        let currentIndex = Int(floor(milesTraveled / spawnInterval))
        let prevIndex = Int(floor(previousMilesTraveled / spawnInterval))
        guard currentIndex > prevIndex else { return nil }

        let pool = AmbientPool.species(trailID: trailID, mile: milesTraveled, band: band)
        guard !pool.isEmpty else { return nil }

        let actor = makeActor(
            index: currentIndex,
            band: band,
            trailID: trailID,
            pool: pool,
            spawnInterval: spawnInterval,
            milesTraveled: milesTraveled,
            date: date,
            context: context
        )
        return actor.species.isNotable ? actor : nil
    }

    // MARK: - Spawn construction

    private static func makeActor(
        index: Int,
        band: AmbientZLayer,
        trailID: String,
        pool: [AmbientSpecies],
        spawnInterval: Double,
        milesTraveled: Double,
        date: Date,
        context: AmbientLayoutContext
    ) -> AmbientActor {
        var rng = SeededRNG(seed: hashSeed(trailID: trailID, band: band, index: index))

        let speciesIdx = rng.nextInt(in: 0..<pool.count)
        let species = pool[speciesIdx]

        // Spawn mile jittered around this slot.
        let jitter = rng.nextDouble(in: -0.25...0.25) * spawnInterval
        let spawnMile = Double(index) * spawnInterval + jitter

        // Spawn date = when the hiker reached this spawn mile. Best we can
        // approximate in a stateless pure function is "date - time to cover
        // (milesTraveled - spawnMile) at current pace". For motion kernels
        // that care only about elapsed time after spawn, we approximate it as
        // `date` shifted back by a small amount — stable across frames since
        // both arguments are stable within a tick.
        let ageMiles = max(0, milesTraveled - spawnMile)
        // Assume ~2 min/mile walking pace for mapping spawn-age to seconds.
        let ageSec = ageMiles * 120.0
        let spawnDate = date.addingTimeInterval(-ageSec)

        let rowFraction = CGFloat(rng.nextDouble(in: 0.05...0.9))
        let initialX = CGFloat(rng.nextDouble(in: 0...1)) * context.bandWidth
        let sizeScale = CGFloat(rng.nextDouble(in: 0.85...1.15))
        let flipH = rng.nextBool()

        let motion = motionFor(species: species, band: band, rng: &rng)

        return AmbientActor(
            id: hashSeed(trailID: trailID, band: band, index: index),
            species: species,
            band: band,
            motion: motion,
            spawnMile: spawnMile,
            spawnDate: spawnDate,
            rowFraction: rowFraction,
            initialX: initialX,
            sizeScale: sizeScale,
            flipH: flipH
        )
    }

    private static func motionFor(
        species: AmbientSpecies,
        band: AmbientZLayer,
        rng: inout SeededRNG
    ) -> AmbientMotion {
        switch species {
        case .cloudSmall, .cloudLarge:
            let dir: CGFloat = rng.nextBool() ? 1 : -1
            return .drift(speed: dir * CGFloat(rng.nextDouble(in: 6...14)))
        case .bird:
            let dir: CGFloat = rng.nextBool() ? 1 : -1
            return .flap(speed: dir * CGFloat(rng.nextDouble(in: 40...70)),
                         amplitude: CGFloat(rng.nextDouble(in: 4...9)),
                         wavelengthSec: rng.nextDouble(in: 1.2...2.2))
        case .birdFlock:
            let dir: CGFloat = rng.nextBool() ? 1 : -1
            return .flap(speed: dir * CGFloat(rng.nextDouble(in: 28...48)),
                         amplitude: 3,
                         wavelengthSec: 2.4)
        case .eagle:
            let dir: CGFloat = rng.nextBool() ? 1 : -1
            return .flap(speed: dir * CGFloat(rng.nextDouble(in: 14...22)),
                         amplitude: CGFloat(rng.nextDouble(in: 2...5)),
                         wavelengthSec: 4.5)
        case .raven where band == .sky:
            let dir: CGFloat = rng.nextBool() ? 1 : -1
            return .flap(speed: dir * CGFloat(rng.nextDouble(in: 20...34)),
                         amplitude: 3,
                         wavelengthSec: 2.0)
        case .raven, .marmot, .deer, .pika, .bear, .hiker:
            return .scroll
        case .squirrel, .butterfly:
            let dir: CGFloat = rng.nextBool() ? 1 : -1
            return .cross(durationSec: rng.nextDouble(in: 2.0...3.5), direction: dir)
        case .rain, .snow:
            return .sheet(speed: CGFloat(rng.nextDouble(in: 1.5...3.5)))
        }
    }

    // MARK: - Render (pure)

    private static func render(
        actor: AmbientActor,
        milesTraveled: Double,
        date: Date,
        context: AmbientLayoutContext
    ) -> AmbientRender? {

        let ageSec = date.timeIntervalSince(actor.spawnDate)

        let spriteHeight = actor.species.displayHeight * actor.sizeScale
        let spriteWidth = spriteHeight * actor.species.aspectRatio
        let bandBottom = context.bandOriginY + context.bandHeight

        switch actor.motion {

        case .drift(let speed):
            let lifespanSec = 90.0
            if ageSec < 0 || ageSec > lifespanSec { return nil }
            let x = actor.initialX + CGFloat(ageSec) * speed
            // Wrap horizontally so clouds that start offscreen still drift in.
            let wrapped = wrap(x: x, width: context.bandWidth, margin: spriteWidth)
            let y = context.bandOriginY + actor.rowFraction * (context.bandHeight - spriteHeight)
            let fade = entryExitFade(age: ageSec, lifespan: lifespanSec, fadeSec: 4.0)
            return AmbientRender(
                id: actor.id,
                species: actor.species,
                assetKey: actor.species.assetKey(frame: frame(for: actor.species, date: date)),
                x: wrapped + spriteWidth / 2,
                y: y + spriteHeight / 2,
                width: spriteWidth,
                height: spriteHeight,
                opacity: fade * 0.85,
                flipH: actor.flipH
            )

        case .flap(let speed, let amplitude, let wavelengthSec):
            let lifespanSec = max(12.0, Double(context.bandWidth / max(1, abs(speed))) * 1.4)
            if ageSec < 0 || ageSec > lifespanSec { return nil }
            // Start fully offscreen on the entry edge, travel to the far edge.
            let startX: CGFloat = speed > 0 ? -spriteWidth : context.bandWidth + spriteWidth
            let x = startX + CGFloat(ageSec) * speed
            // Bail once past exit edge.
            if speed > 0 && x > context.bandWidth + spriteWidth { return nil }
            if speed < 0 && x < -spriteWidth * 2 { return nil }
            let bobPhase = (ageSec.truncatingRemainder(dividingBy: wavelengthSec)) / wavelengthSec
            let bob = sin(bobPhase * 2 * .pi) * Double(amplitude)
            let baseY = context.bandOriginY + actor.rowFraction * (context.bandHeight - spriteHeight)
            let y = baseY + CGFloat(bob)
            let fade = entryExitFade(age: ageSec, lifespan: lifespanSec, fadeSec: 2.5)
            return AmbientRender(
                id: actor.id,
                species: actor.species,
                assetKey: actor.species.assetKey(frame: frame(for: actor.species, date: date)),
                x: x + spriteWidth / 2,
                y: y + spriteHeight / 2,
                width: spriteWidth,
                height: spriteHeight,
                opacity: fade,
                flipH: speed < 0 ? !actor.flipH : actor.flipH
            )

        case .cross(let durationSec, let direction):
            if ageSec < 0 || ageSec > durationSec { return nil }
            let progress = ageSec / durationSec
            let startX: CGFloat = direction > 0 ? -spriteWidth : context.bandWidth + spriteWidth
            let endX: CGFloat = direction > 0 ? context.bandWidth + spriteWidth : -spriteWidth
            let x = startX + (endX - startX) * CGFloat(progress)
            let y = context.bandOriginY + actor.rowFraction * (context.bandHeight - spriteHeight)
            let fade = entryExitFade(age: ageSec, lifespan: durationSec, fadeSec: 0.4)
            return AmbientRender(
                id: actor.id,
                species: actor.species,
                assetKey: actor.species.assetKey(frame: frame(for: actor.species, date: date)),
                x: x + spriteWidth / 2,
                y: y + spriteHeight / 2,
                width: spriteWidth,
                height: spriteHeight,
                opacity: fade,
                flipH: direction < 0 ? !actor.flipH : actor.flipH
            )

        case .scroll:
            // Spawn ~0.6 mi ahead of the hiker and expire ~0.3 mi past.
            let worldOffsetMiles = actor.spawnMile - milesTraveled
            if worldOffsetMiles < -0.35 { return nil }
            if worldOffsetMiles > 0.9 { return nil }
            let screenX = context.hikerScreenX + CGFloat(worldOffsetMiles) * context.pxPerMile
            // Cull if fully offscreen either side.
            if screenX < -spriteWidth || screenX > context.bandWidth + spriteWidth { return nil }

            // Distance and foreground actors stand with feet near the bottom of their band.
            let footY: CGFloat
            switch actor.band {
            case .foreground:
                footY = bandBottom
            case .distance:
                // Slightly lifted, silhouettes rest on top of the hills.
                footY = bandBottom - 4
            case .sky:
                footY = bandBottom
            }
            let y = footY - spriteHeight / 2
            // Fade in/out at the approach/exit edges.
            let fadeIn = smoothstep(Double((0.9 - worldOffsetMiles) / 0.25).clamped(to: 0...1))
            let fadeOut = smoothstep(Double((worldOffsetMiles + 0.35) / 0.2).clamped(to: 0...1))
            // Pass-by fade — foreground actors would visually overlap the main
            // hiker as they cross its fixed screen position. Fade them out
            // inside a small dead-zone so they appear to pass off to the side.
            var passByFade = 1.0
            if actor.band == .foreground {
                let deadZone: CGFloat = actor.species == .hiker ? 70 : 40
                let distance = abs(screenX - context.hikerScreenX)
                if distance < deadZone {
                    passByFade = smoothstep(Double(distance / deadZone))
                }
            }
            let fade = min(fadeIn, fadeOut) * passByFade
            return AmbientRender(
                id: actor.id,
                species: actor.species,
                assetKey: actor.species.assetKey(frame: frame(for: actor.species, date: date)),
                x: screenX,
                y: y,
                width: spriteWidth,
                height: spriteHeight,
                opacity: fade * bandOpacity(actor.band),
                flipH: actor.flipH
            )

        case .sheet(let speed):
            let lifespanSec = 120.0
            if ageSec < 0 || ageSec > lifespanSec { return nil }
            let x = actor.initialX + CGFloat(ageSec) * speed
            let wrapped = wrap(x: x, width: context.bandWidth, margin: spriteWidth)
            let y = context.bandOriginY
            let fade = entryExitFade(age: ageSec, lifespan: lifespanSec, fadeSec: 6.0)
            return AmbientRender(
                id: actor.id,
                species: actor.species,
                assetKey: actor.species.assetKey(frame: 0),
                x: wrapped + spriteWidth / 2,
                y: y + context.bandHeight / 2,
                width: context.bandWidth,
                height: context.bandHeight,
                opacity: fade * 0.45,
                flipH: false
            )
        }
    }

    private static func bandOpacity(_ band: AmbientZLayer) -> Double {
        switch band {
        case .sky:        return 0.9
        case .distance:   return 0.75
        case .foreground: return 0.95
        }
    }

    private static func frame(for species: AmbientSpecies, date: Date) -> Int {
        let period = species.framePeriod
        guard period < 1.0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        return Int(t / period)
    }

    private static func entryExitFade(age: Double, lifespan: Double, fadeSec: Double) -> Double {
        let fadeIn = smoothstep((age / max(0.001, fadeSec)).clamped(to: 0...1))
        let fadeOut = smoothstep(((lifespan - age) / max(0.001, fadeSec)).clamped(to: 0...1))
        return min(fadeIn, fadeOut)
    }

    private static func wrap(x: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let total = width + margin * 2
        let shifted = x + margin
        let m = shifted.truncatingRemainder(dividingBy: total)
        let wrapped = m < 0 ? m + total : m
        return wrapped - margin
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = t.clamped(to: 0...1)
        return x * x * (3 - 2 * x)
    }

    // MARK: - Deterministic hashing

    private static func hashSeed(trailID: String, band: AmbientZLayer, index: Int) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in trailID.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        for b in band.rawValue.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        h ^= UInt64(bitPattern: Int64(index))
        h = h &* 0x100000001b3
        return Int(truncatingIfNeeded: h)
    }
}

// MARK: - Small helpers

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
    mutating func nextInt(in range: Range<Int>) -> Int {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(span))
    }
    mutating func nextBool() -> Bool {
        next() & 1 == 0
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
