import SwiftUI

/// Registry of programmatic pixel-art sprites keyed by asset name.
/// `PixelImage` and `ParallaxLayer` look up art here first; when a key is
/// missing they fall back to `Assets.xcassets` (or the magenta debug box).
enum PixelArtRegistry {
    static let all: [String: PixelSprite] = [
        // Hiker walk cycle (4 frames)
        "hiker.walk.0": HikerArt.frame0,
        "hiker.walk.1": HikerArt.frame1,
        "hiker.walk.2": HikerArt.frame2,
        "hiker.walk.3": HikerArt.frame3,

        // Landmarks — John Muir Trail
        "landmark.jmt.happy_isles":          LandmarkArt.happyIsles,
        "landmark.jmt.half_dome":            LandmarkArt.halfDome,
        "landmark.jmt.cathedral_peak":       LandmarkArt.cathedralPeak,
        "landmark.jmt.tuolumne_meadows":     LandmarkArt.tuolumneMeadows,
        "landmark.jmt.thousand_island_lake": LandmarkArt.thousandIslandLake,
        "landmark.jmt.muir_pass":            LandmarkArt.muirPass,
        "landmark.jmt.forester_pass":        LandmarkArt.foresterPass,
        "landmark.jmt.mt_whitney":           LandmarkArt.mtWhitney,

        // Badges
        "badge.cautious_hiker":       BadgeArt.cautiousHiker,
        "badge.trailblazer":          BadgeArt.trailblazer,
        "badge.good_samaritan":       BadgeArt.goodSamaritan,
        "badge.storm_chaser":         BadgeArt.stormChaser,
        "badge.peak_bagger":          BadgeArt.peakBagger,
        "badge.ultralight":           BadgeArt.ultralight,
        "badge.lost_hiker_saved":     BadgeArt.lostHikerSaved,
        "badge.bear_canister_master": BadgeArt.bearCanisterMaster,
        "badge.sierra_storyteller":   BadgeArt.sierraStoryteller,

        // Parallax layers
        "parallax.jmt.sky":       ParallaxArt.skyJMT,
        "parallax.jmt.mountains": ParallaxArt.mountainsJMT,
        "parallax.jmt.hills":     ParallaxArt.hillsJMT,
        "parallax.jmt.ground":    ParallaxArt.groundJMT,

        // Finale hero scene
        "finale.jmt": FinaleArt.jmt,

        // Ambient encounters (wildlife, weather, fellow hikers)
        "ambient.cloud.small":      AmbientArt.cloudSmall,
        "ambient.cloud.large":      AmbientArt.cloudLarge,
        "ambient.bird.flap.0":      AmbientArt.birdFlap0,
        "ambient.bird.flap.1":      AmbientArt.birdFlap1,
        "ambient.bird.flock":       AmbientArt.birdFlock,
        "ambient.eagle.glide":      AmbientArt.eagleGlide,
        "ambient.raven":            AmbientArt.raven,
        "ambient.marmot.sit":       AmbientArt.marmotSit,
        "ambient.deer.stand":       AmbientArt.deerStand,
        "ambient.squirrel.run.0":   AmbientArt.squirrelRun0,
        "ambient.squirrel.run.1":   AmbientArt.squirrelRun1,
        "ambient.hiker.distant.0":  AmbientArt.hikerDistant0,
        "ambient.hiker.distant.1":  AmbientArt.hikerDistant1,
        "ambient.butterfly.0":      AmbientArt.butterfly0,
        "ambient.butterfly.1":      AmbientArt.butterfly1,
        "ambient.pika":             AmbientArt.pika,
        "ambient.bear.distant":     AmbientArt.bearDistant,
        "ambient.rain.sheet":       AmbientArt.rainSheet,
        "ambient.snow.sheet":       AmbientArt.snowSheet
    ]
}

// MARK: - Hiker walk cycle (32×48)

private enum HikerArt {
    // Draw everything above the feet. Legs/boots drawn by each frame.
    static func upperBody(_ c: PixelCanvas, bob: Int = 0) {
        let p = ArtPalette.self
        // Hat crown
        c.rect(12, 1 + bob, 8, 1, p.deep)
        c.rect(11, 2 + bob, 10, 3, p.deep)
        // Hat brim (wider)
        c.rect(9, 5 + bob, 14, 1, p.deep)
        c.rect(10, 6 + bob, 12, 1, p.brown)
        // Face
        c.rect(12, 7 + bob, 8, 4, p.skin)
        // Eyes
        c.px(14, 9 + bob, p.deep)
        c.px(17, 9 + bob, p.deep)
        // Chin shadow
        c.rect(13, 10 + bob, 6, 1, p.brown)
        // Neck
        c.rect(14, 11 + bob, 4, 1, p.skin)
        // Pack peeking above shoulders
        c.rect(13, 11 + bob, 6, 2, p.green)
        c.rect(14, 10 + bob, 4, 1, p.green)
        // Torso / shirt
        c.rect(11, 13 + bob, 10, 11, p.coral)
        // Pack straps over shoulders
        c.rect(11, 13 + bob, 1, 11, p.mountBlue)
        c.rect(20, 13 + bob, 1, 11, p.mountBlue)
        // Chest horizontal strap
        c.rect(11, 17 + bob, 10, 1, p.mountBlue)
        // Arms
        c.rect(9, 14 + bob, 2, 9, p.coral)
        c.rect(21, 14 + bob, 2, 9, p.coral)
        // Hands
        c.rect(9, 23 + bob, 2, 2, p.skin)
        c.rect(21, 23 + bob, 2, 2, p.skin)
        // Belt
        c.rect(11, 24 + bob, 10, 1, p.brown)
    }

    static let frame0 = PixelSprite(width: 32, height: 48) { c in
        let p = ArtPalette.self
        upperBody(c, bob: 0)
        // Passing stance — feet close together
        c.rect(12, 25, 3, 13, p.mountBlue)
        c.rect(17, 25, 3, 13, p.mountBlue)
        // Boots
        c.rect(11, 38, 5, 3, p.deep)
        c.rect(16, 38, 5, 3, p.deep)
    }

    static let frame1 = PixelSprite(width: 32, height: 48) { c in
        let p = ArtPalette.self
        upperBody(c, bob: -1)
        // Step right — left leg back & bent, right leg forward
        // Back leg
        c.rect(11, 25, 3, 10, p.mountBlue)
        c.rect(9, 35, 5, 3, p.mountBlue)  // angled back
        c.rect(8, 38, 4, 2, p.deep)        // back boot
        // Front leg
        c.rect(18, 25, 3, 11, p.mountBlue)
        c.rect(19, 36, 4, 2, p.mountBlue)  // angled forward
        c.rect(20, 38, 5, 3, p.deep)        // front boot
    }

    static let frame2 = PixelSprite(width: 32, height: 48) { c in
        let p = ArtPalette.self
        upperBody(c, bob: 0)
        // Mirror of frame0 — passing stance (slightly different for variation)
        c.rect(13, 25, 3, 13, p.mountBlue)
        c.rect(16, 25, 3, 13, p.mountBlue)
        // Boots slightly apart
        c.rect(12, 38, 4, 3, p.deep)
        c.rect(16, 38, 4, 3, p.deep)
    }

    static let frame3 = PixelSprite(width: 32, height: 48) { c in
        let p = ArtPalette.self
        upperBody(c, bob: -1)
        // Step left — mirror of frame1
        // Back leg (right back)
        c.rect(18, 25, 3, 10, p.mountBlue)
        c.rect(18, 35, 5, 3, p.mountBlue)
        c.rect(20, 38, 4, 2, p.deep)
        // Front leg (left forward)
        c.rect(11, 25, 3, 11, p.mountBlue)
        c.rect(9, 36, 4, 2, p.mountBlue)
        c.rect(7, 38, 5, 3, p.deep)
    }
}

// MARK: - Landmarks (48×48 each)

private enum LandmarkArt {
    // Draws a small pine tree at position (x, y) where y is the bottom.
    static func pine(_ c: PixelCanvas, x: Int, y: Int, size: Int = 3) {
        let p = ArtPalette.self
        c.rect(x, y - size, 1, size, p.treeDark)
        c.rect(x - 1, y - size + 1, 3, 1, p.green)
        if size >= 3 {
            c.rect(x - 1, y - 1, 3, 1, p.green)
        }
    }

    static let happyIsles = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        // Sky
        c.rect(0, 0, 48, 28, p.sky)
        // Forest backdrop
        c.rect(0, 20, 48, 10, p.treeDark)
        for x in stride(from: 0, to: 48, by: 4) {
            c.rect(x, 17, 3, 4, p.green)
        }
        // Distant peaks
        c.rect(5, 12, 10, 8, p.mountDark)
        c.rect(7, 10, 6, 2, p.mountLight)
        c.rect(28, 14, 12, 6, p.mountDark)
        c.rect(30, 12, 8, 2, p.mountLight)
        // Water / river flowing under
        c.rect(0, 34, 48, 10, p.water)
        c.rect(0, 34, 48, 1, p.waterLight)
        c.rect(0, 38, 48, 1, p.waterLight)
        c.rect(0, 42, 48, 1, p.waterLight)
        // Stone bridge — arch
        c.rect(8, 26, 32, 8, p.stone)
        c.rect(8, 25, 32, 1, p.stoneLight)
        c.rect(10, 27, 28, 1, p.stoneDark)
        // Bridge railings
        c.rect(8, 24, 2, 2, p.stoneDark)
        c.rect(38, 24, 2, 2, p.stoneDark)
        for x in stride(from: 11, to: 38, by: 3) {
            c.rect(x, 22, 1, 3, p.stoneDark)
        }
        c.rect(10, 21, 28, 1, p.stoneDark)
        // Arch opening
        c.rect(19, 30, 10, 4, p.deep)
        c.rect(20, 29, 8, 1, p.deep)
        // Ground at bridge ends
        c.rect(0, 32, 8, 4, p.grassDark)
        c.rect(40, 32, 8, 4, p.grassDark)
        c.rect(0, 30, 8, 2, p.grass)
        c.rect(40, 30, 8, 2, p.grass)
        // Water ripples under the arch
        c.rect(20, 40, 2, 1, p.waterLight)
        c.rect(24, 41, 3, 1, p.waterLight)
        c.rect(28, 39, 2, 1, p.waterLight)
    }

    static let halfDome = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        // Sky
        c.rect(0, 0, 48, 44, p.sky)
        // Ground strip
        c.rect(0, 42, 48, 6, p.grassDark)
        c.rect(0, 40, 48, 2, p.grass)
        // Distant peak (right, behind)
        let farPeak: [Int] = Array(repeating: 0, count: 28) + [0, 2, 5, 8, 11, 9, 6, 3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        c.silhouette(heights: Array(farPeak.prefix(48)), baselineY: 40, color: p.mountDark)
        // Half Dome — flat cliff on the left, dome curving down to the right
        let dome: [Int] = [
            0,  0,  0,  0,  0,  0,                       //  0–5
            6,  11, 17, 22, 25, 28,                      //  6–11 cliff rising
            30, 31, 31, 31, 31, 31,                      // 12–17 flat top
            31, 31, 31, 31, 31, 30,                      // 18–23
            29, 28, 27, 25, 23, 21,                      // 24–29
            18, 15, 12,  9,  6,  4,                      // 30–35 sloping right
            2,  1,  0,  0,  0,  0,                       // 36–41
            0,  0,  0,  0,  0,  0                        // 42–47
        ]
        c.silhouette(heights: dome, baselineY: 40, color: p.stone)
        // Shadow side (cliff face)
        for x in 7...11 {
            let top = 40 - dome[x] + 1
            c.col(x, from: top, to: 40, p.stoneDark)
        }
        c.col(12, from: 10, to: 40, p.stoneDark)
        // Vertical crack lines on cliff
        c.col(8, from: 18, to: 38, p.deep)
        c.col(10, from: 16, to: 38, p.deep)
        // Highlight top edge
        c.row(9, from: 13, to: 28, p.stoneLight)
        c.row(10, from: 12, to: 29, p.stoneLight)
        // Snow on the summit
        c.row(8, from: 15, to: 26, p.snow)
        c.row(7, from: 17, to: 24, p.snow)
        // Trees at base
        pine(c, x: 2, y: 42)
        pine(c, x: 5, y: 42, size: 4)
        pine(c, x: 43, y: 42, size: 4)
        pine(c, x: 46, y: 42)
    }

    static let cathedralPeak = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        c.rect(0, 0, 48, 44, p.sky)
        c.rect(0, 42, 48, 6, p.grassDark)
        c.rect(0, 40, 48, 2, p.grass)
        // Rocky base
        c.rect(4, 32, 40, 9, p.stone)
        c.rect(4, 31, 40, 1, p.stoneLight)
        // Left (taller) spire
        let spireL: [Int] = [
            0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,4,8,12,16,20,22,24,    // x=12-23 rising
            26,28,30,32,30,28,26,24,          // x=24-31 peak
            22,20,18,16,14,12,10,8,6,4,2,0,0,0,0,0
        ]
        c.silhouette(heights: spireL, baselineY: 40, color: p.stoneDark)
        // Right (shorter) spire
        let spireR: [Int] = [
            0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,
            0,0,0,0,0,3,6,10,13,16,19,21,22,22,20,16
        ]
        c.silhouette(heights: spireR, baselineY: 40, color: p.stone)
        // Highlights on the tall spire
        c.rect(27, 10, 2, 8, p.stoneLight)
        c.rect(25, 14, 2, 6, p.stoneLight)
        // Snow dabs near peaks
        c.px(28, 9, p.snow)
        c.px(27, 10, p.snow)
        c.px(43, 19, p.snow)
        c.px(42, 20, p.snow)
        // Forest at base
        pine(c, x: 2, y: 41, size: 3)
        pine(c, x: 5, y: 41, size: 4)
        pine(c, x: 8, y: 41, size: 3)
        pine(c, x: 38, y: 41, size: 3)
        pine(c, x: 41, y: 41, size: 4)
        pine(c, x: 45, y: 41, size: 3)
    }

    static let tuolumneMeadows = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        // Sky
        c.rect(0, 0, 48, 20, p.sky)
        // Distant granite peaks
        let peaks: [Int] = [
            2, 4, 6, 8, 10, 12, 10, 8,
            6, 4, 2, 3, 6, 8, 10, 11,
            10, 9, 8, 7, 6, 6, 8, 10,
            12, 14, 12, 10, 8, 6, 4, 3,
            4, 6, 8, 10, 12, 14, 13, 11,
            9, 7, 5, 3, 2, 2, 1, 0
        ]
        c.silhouette(heights: peaks, baselineY: 22, color: p.mountBlue)
        // Snow on highest peaks
        for x in 0..<48 where peaks[x] >= 12 {
            c.px(x, 22 - peaks[x] + 1, p.snow)
            c.px(x, 22 - peaks[x] + 2, p.snow)
        }
        // Tree line
        c.rect(0, 22, 48, 3, p.treeDark)
        for x in stride(from: 0, to: 48, by: 3) {
            c.rect(x, 20, 2, 3, p.green)
        }
        // Meadow
        c.rect(0, 25, 48, 23, p.grass)
        // Grass detail strokes
        for x in stride(from: 1, to: 48, by: 4) {
            c.px(x, 27, p.grassDark)
            c.px(x + 2, 29, p.grassDark)
            c.px(x, 31, p.grassDark)
        }
        // Lyell Fork (winding river)
        c.rect(2, 34, 44, 3, p.water)
        c.rect(2, 34, 44, 1, p.waterLight)
        c.rect(6, 33, 8, 1, p.water)
        c.rect(22, 33, 10, 1, p.water)
        c.rect(38, 35, 6, 1, p.waterLight)
        // Wildflowers
        c.px(10, 40, p.coral)
        c.px(18, 42, p.coral)
        c.px(27, 39, p.sunrise)
        c.px(35, 43, p.coral)
        c.px(40, 40, p.sunrise)
        // A lone pine
        pine(c, x: 14, y: 34, size: 4)
        pine(c, x: 34, y: 34, size: 3)
    }

    static let thousandIslandLake = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        // Sky
        c.rect(0, 0, 48, 18, p.sky)
        // Banner Peak silhouette (triangular)
        let banner: [Int] = [
            0, 0, 0, 2, 4, 6, 8, 10,
            12, 14, 16, 18, 20, 22, 24, 26,
            28, 28, 26, 24, 22, 20, 18, 16,
            14, 12, 10, 8, 6, 4, 2, 0,
            0, 0, 0, 2, 4, 6, 8, 10,
            12, 10, 8, 6, 4, 2, 0, 0
        ]
        c.silhouette(heights: banner, baselineY: 22, color: p.mountBlue)
        // Snow on Banner's peak
        for x in 15...20 {
            c.px(x, 22 - banner[x] + 1, p.snow)
            c.px(x, 22 - banner[x] + 2, p.snow)
        }
        c.px(16, 22 - banner[16], p.snow)
        c.px(17, 22 - banner[17], p.snow)
        // Far shore tree line
        c.rect(0, 22, 48, 2, p.treeDark)
        // Lake
        c.rect(0, 24, 48, 20, p.water)
        // Water ripples
        c.rect(2, 26, 6, 1, p.waterLight)
        c.rect(12, 28, 8, 1, p.waterLight)
        c.rect(24, 27, 10, 1, p.waterLight)
        c.rect(38, 29, 8, 1, p.waterLight)
        c.rect(4, 33, 40, 1, p.waterLight)
        c.rect(6, 37, 30, 1, p.waterLight)
        // Tiny islands (the "thousand")
        c.rect(8, 32, 4, 2, p.stone)
        c.px(9, 31, p.treeDark)
        c.rect(20, 30, 3, 1, p.stone)
        c.px(21, 29, p.treeDark)
        c.rect(30, 34, 5, 2, p.stone)
        c.rect(32, 33, 2, 1, p.treeDark)
        c.rect(40, 31, 3, 1, p.stone)
        // Shore
        c.rect(0, 44, 48, 4, p.grassDark)
        c.rect(0, 43, 48, 1, p.grass)
    }

    static let muirPass = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        // Sky
        c.rect(0, 0, 48, 30, p.sky)
        // Snowy ridge in the distance
        let ridge: [Int] = [
            4, 6, 8, 10, 12, 14, 16, 14,
            12, 10, 12, 14, 16, 18, 16, 14,
            12, 14, 16, 18, 20, 18, 16, 14,
            12, 10, 12, 14, 16, 18, 16, 14,
            12, 10, 8, 10, 12, 14, 12, 10,
            8, 6, 4, 3, 2, 1, 0, 0
        ]
        c.silhouette(heights: ridge, baselineY: 30, color: p.mountDark)
        // Snow across the ridge
        for x in 0..<48 where ridge[x] >= 10 {
            c.px(x, 30 - ridge[x] + 1, p.snow)
            if ridge[x] >= 14 {
                c.px(x, 30 - ridge[x] + 2, p.snow)
            }
        }
        // Alpine ground
        c.rect(0, 30, 48, 18, p.grassDark)
        c.rect(0, 30, 48, 1, p.stone)
        // Scattered rocks
        c.rect(3, 36, 3, 2, p.stone)
        c.rect(42, 38, 4, 2, p.stone)
        c.rect(8, 42, 2, 2, p.stoneDark)
        c.rect(36, 41, 3, 2, p.stoneDark)
        // The famous stone hut — rounded dome
        c.rect(18, 32, 12, 10, p.stone)
        c.rect(19, 31, 10, 1, p.stone)
        c.rect(20, 30, 8, 1, p.stone)
        c.rect(22, 29, 4, 1, p.stone)
        // Hut stones (random blocks)
        c.row(34, from: 18, to: 29, p.stoneDark)
        c.px(21, 36, p.stoneDark)
        c.px(26, 37, p.stoneDark)
        c.px(20, 39, p.stoneDark)
        c.px(27, 40, p.stoneDark)
        c.px(23, 35, p.stoneLight)
        c.px(25, 38, p.stoneLight)
        // Door
        c.rect(22, 36, 4, 6, p.deep)
        c.rect(23, 37, 2, 4, p.brown)
        // Door arch
        c.px(22, 36, p.stoneDark)
        c.px(25, 36, p.stoneDark)
    }

    static let foresterPass = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        c.rect(0, 0, 48, 48, p.sky)
        // Jagged knife-edge ridge
        let ridge: [Int] = [
            0, 0, 4, 8, 12, 16, 20, 22,
            24, 26, 28, 26, 24, 28, 32, 34,
            36, 38, 40, 38, 36, 34, 32, 30,
            32, 34, 32, 28, 24, 26, 28, 26,
            22, 18, 20, 22, 18, 14, 10, 12,
            14, 10, 6, 4, 2, 0, 0, 0
        ]
        c.silhouette(heights: ridge, baselineY: 44, color: p.mountBlue)
        // Shadow on one side of the ridge (darker)
        for x in 0..<48 {
            let h = ridge[x]
            if h > 0 {
                let top = 44 - h + 1
                // Draw right-side shadow
                if x > 0 && ridge[x - 1] < h {
                    c.col(x, from: top, to: min(top + h / 3, 44), p.mountDark)
                }
            }
        }
        // Snow on the highest peak
        for x in 14...21 where ridge[x] >= 30 {
            c.px(x, 44 - ridge[x] + 1, p.snow)
            c.px(x, 44 - ridge[x] + 2, p.snow)
            if ridge[x] >= 36 {
                c.px(x, 44 - ridge[x] + 3, p.snow)
            }
        }
        // Foreground rocky scree
        c.rect(0, 44, 48, 4, p.stoneDark)
        c.px(5, 45, p.stone)
        c.px(10, 46, p.stone)
        c.px(18, 45, p.stone)
        c.px(30, 46, p.stone)
        c.px(40, 45, p.stone)
        // Thin clouds high above
        c.rect(4, 6, 8, 1, p.cloudGray)
        c.rect(35, 4, 9, 1, p.cloudGray)
    }

    static let mtWhitney = PixelSprite(width: 48, height: 48) { c in
        let p = ArtPalette.self
        c.rect(0, 0, 48, 48, p.sky)
        // A softer sunrise tint near the horizon
        c.rect(0, 38, 48, 4, p.sunrise.opacity(0.35))
        // Subordinate peaks behind
        let back: [Int] = [
            0, 0, 2, 6, 10, 8, 6, 4,
            2, 0, 0, 2, 6, 10, 14, 12,
            10, 8, 6, 4, 2, 0, 0, 0,
            0, 0, 0, 0, 2, 6, 10, 8,
            6, 4, 2, 0, 0, 2, 6, 10,
            8, 6, 4, 2, 0, 0, 0, 0
        ]
        c.silhouette(heights: back, baselineY: 42, color: p.mountDark)
        // The main peak — sharp, tall, centered
        let whitney: [Int] = [
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 2, 6, 10, 14,
            18, 22, 26, 30, 33, 36, 38, 40,
            40, 38, 36, 33, 30, 26, 22, 18,
            14, 10, 6, 2, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        ]
        c.silhouette(heights: whitney, baselineY: 44, color: p.stoneDark)
        // Lighter rock highlight on one face
        for x in 16...23 {
            let top = 44 - whitney[x] + 1
            c.col(x, from: top, to: top + whitney[x] / 3, p.stone)
        }
        // Deep snow cap
        for x in 0..<48 where whitney[x] >= 30 {
            c.px(x, 44 - whitney[x] + 1, p.snow)
            if whitney[x] >= 34 {
                c.px(x, 44 - whitney[x] + 2, p.snow)
            }
            if whitney[x] >= 38 {
                c.px(x, 44 - whitney[x] + 3, p.snow)
            }
        }
        // Tiny summit shelter at the very top
        c.rect(23, 3, 3, 2, p.stoneDark)
        c.rect(22, 4, 5, 1, p.stoneDark)
        // Base / boulders
        c.rect(0, 44, 48, 4, p.stoneDark)
        c.px(6, 45, p.stone)
        c.px(18, 46, p.stone)
        c.px(36, 45, p.stone)
        c.px(43, 46, p.stone)
    }
}

// MARK: - Badges (32×32)

private enum BadgeArt {
    /// Common round-ish badge plate with a given accent and interior draw block.
    static func plate(_ c: PixelCanvas, tint: Color, interior: (PixelCanvas) -> Void) {
        let p = ArtPalette.self
        // Ribbon/outer ring
        c.rect(4, 4, 24, 24, tint)
        c.rect(6, 2, 20, 2, tint)
        c.rect(6, 28, 20, 2, tint)
        c.rect(2, 6, 2, 20, tint)
        c.rect(28, 6, 2, 20, tint)
        // Inner parchment face
        c.rect(6, 6, 20, 20, p.parchment)
        c.rect(6, 6, 20, 1, p.sand)
        c.rect(6, 25, 20, 1, p.sand)
        c.rect(6, 6, 1, 20, p.sand)
        c.rect(25, 6, 1, 20, p.sand)
        interior(c)
    }

    static let cautiousHiker = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.forestGreen(opacity: 1.0)) { c in
            let p = ArtPalette.self
            // Shield shape
            c.rect(12, 9, 8, 2, p.mountBlue)
            c.rect(11, 11, 10, 8, p.mountBlue)
            c.rect(12, 19, 8, 2, p.mountBlue)
            c.rect(13, 21, 6, 1, p.mountBlue)
            c.rect(14, 22, 4, 1, p.mountBlue)
            c.px(15, 23, p.mountBlue)
            c.px(16, 23, p.mountBlue)
            // Checkmark
            c.px(13, 15, p.parchment)
            c.px(14, 16, p.parchment)
            c.px(15, 17, p.parchment)
            c.px(16, 16, p.parchment)
            c.px(17, 15, p.parchment)
            c.px(18, 14, p.parchment)
            c.px(19, 13, p.parchment)
        }
    }

    static let trailblazer = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.coral) { c in
            let p = ArtPalette.self
            // A pair of boots
            // Left boot
            c.rect(9, 16, 5, 6, p.brown)
            c.rect(8, 20, 7, 2, p.brown)
            c.rect(9, 22, 6, 1, p.deep)
            // Laces
            c.px(10, 17, p.sand)
            c.px(12, 17, p.sand)
            c.px(10, 19, p.sand)
            c.px(12, 19, p.sand)
            // Right boot
            c.rect(18, 14, 5, 8, p.brown)
            c.rect(17, 20, 7, 2, p.brown)
            c.rect(18, 22, 6, 1, p.deep)
            c.px(19, 15, p.sand)
            c.px(21, 15, p.sand)
            c.px(19, 17, p.sand)
            c.px(21, 17, p.sand)
            c.px(19, 19, p.sand)
            c.px(21, 19, p.sand)
        }
    }

    static let goodSamaritan = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.coral) { c in
            let p = ArtPalette.self
            // Heart shape
            c.rect(10, 11, 4, 2, p.coral)
            c.rect(18, 11, 4, 2, p.coral)
            c.rect(9, 13, 6, 2, p.coral)
            c.rect(17, 13, 6, 2, p.coral)
            c.rect(9, 15, 14, 3, p.coral)
            c.rect(10, 18, 12, 2, p.coral)
            c.rect(11, 20, 10, 1, p.coral)
            c.rect(12, 21, 8, 1, p.coral)
            c.rect(13, 22, 6, 1, p.coral)
            c.rect(14, 23, 4, 1, p.coral)
            c.px(15, 24, p.coral)
            c.px(16, 24, p.coral)
            // Highlight
            c.px(11, 13, p.parchment)
            c.px(12, 14, p.parchment)
        }
    }

    static let stormChaser = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.mountBlue) { c in
            let p = ArtPalette.self
            // Cloud
            c.rect(10, 10, 12, 5, p.cloudGray)
            c.rect(8, 12, 2, 3, p.cloudGray)
            c.rect(22, 12, 2, 3, p.cloudGray)
            c.rect(12, 8, 8, 2, p.cloudGray)
            // Cloud shadow underside
            c.rect(10, 14, 12, 1, p.stoneDark)
            // Lightning bolt
            c.rect(15, 15, 3, 2, p.sunrise)
            c.rect(14, 17, 3, 2, p.sunrise)
            c.rect(16, 19, 3, 2, p.sunrise)
            c.rect(15, 21, 2, 2, p.sunrise)
            c.rect(13, 23, 4, 1, p.sunrise)
        }
    }

    static let peakBagger = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.stoneDark) { c in
            let p = ArtPalette.self
            // Mountain silhouette
            let peak: [Int] = [
                0, 0, 1, 3, 5, 8, 11, 13,
                15, 13, 11, 8, 10, 12, 10, 7,
                5, 3, 1, 0
            ]
            for (i, h) in peak.enumerated() where h > 0 {
                c.col(7 + i, from: 22 - h + 1, to: 22, p.stoneDark)
            }
            // Snow cap on top
            c.px(14, 10, p.snow)
            c.px(15, 9, p.snow)
            c.px(13, 11, p.snow)
            // Flag
            c.rect(16, 4, 1, 6, p.brown)
            c.rect(17, 4, 4, 3, p.coral)
        }
    }

    static let ultralight = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.forestGreen(opacity: 1.0)) { c in
            let p = ArtPalette.self
            // Stylized feather
            let spine = 16
            c.rect(spine, 9, 1, 14, p.brown)
            // Barbs left
            c.rect(13, 11, 3, 1, p.green)
            c.rect(12, 13, 4, 1, p.green)
            c.rect(11, 15, 5, 1, p.green)
            c.rect(12, 17, 4, 1, p.green)
            c.rect(13, 19, 3, 1, p.green)
            c.rect(14, 21, 2, 1, p.green)
            // Barbs right
            c.rect(17, 11, 3, 1, p.green)
            c.rect(17, 13, 4, 1, p.green)
            c.rect(17, 15, 5, 1, p.green)
            c.rect(17, 17, 4, 1, p.green)
            c.rect(17, 19, 3, 1, p.green)
            c.rect(17, 21, 2, 1, p.green)
            // Tip curl
            c.px(16, 8, p.brown)
            c.px(17, 8, p.brown)
        }
    }

    static let lostHikerSaved = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.mountBlue) { c in
            let p = ArtPalette.self
            // Compass body
            c.rect(10, 10, 12, 12, p.metal)
            c.rect(11, 9, 10, 1, p.metal)
            c.rect(11, 22, 10, 1, p.metal)
            c.rect(9, 11, 1, 10, p.metal)
            c.rect(22, 11, 1, 10, p.metal)
            // Face
            c.rect(11, 11, 10, 10, p.parchment)
            // Cardinal marks
            c.px(16, 11, p.deep)
            c.px(16, 20, p.deep)
            c.px(11, 16, p.deep)
            c.px(20, 16, p.deep)
            // Needle (north pointing)
            c.rect(16, 12, 1, 5, p.coral)  // N half
            c.rect(15, 16, 1, 4, p.deep)   // S half
            c.rect(17, 16, 1, 4, p.deep)
            c.rect(16, 15, 1, 2, p.coral)
            // Center pin
            c.px(16, 16, p.sunrise)
        }
    }

    static let bearCanisterMaster = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.brown) { c in
            let p = ArtPalette.self
            // Bear face circle
            c.rect(11, 11, 10, 10, p.bear)
            c.rect(12, 10, 8, 1, p.bear)
            c.rect(12, 21, 8, 1, p.bear)
            c.rect(10, 12, 1, 8, p.bear)
            c.rect(21, 12, 1, 8, p.bear)
            // Ears
            c.rect(10, 9, 3, 3, p.bear)
            c.rect(19, 9, 3, 3, p.bear)
            c.px(11, 10, p.brown)
            c.px(20, 10, p.brown)
            // Muzzle
            c.rect(14, 17, 4, 3, p.sand)
            c.rect(15, 16, 2, 1, p.sand)
            // Nose
            c.rect(15, 17, 2, 1, p.deep)
            // Eyes
            c.px(13, 14, p.sunrise)
            c.px(18, 14, p.sunrise)
            c.px(13, 13, p.deep)
            c.px(18, 13, p.deep)
        }
    }

    static let sierraStoryteller = PixelSprite(width: 32, height: 32) { c in
        plate(c, tint: ArtPalette.sand) { c in
            let p = ArtPalette.self
            // Open book
            // Left page
            c.rect(8, 11, 8, 12, p.paperYellow)
            // Right page
            c.rect(16, 11, 8, 12, p.paperYellow)
            // Book spine (center)
            c.rect(15, 10, 2, 14, p.brown)
            // Outer covers
            c.rect(7, 10, 1, 14, p.deep)
            c.rect(24, 10, 1, 14, p.deep)
            c.rect(8, 10, 7, 1, p.deep)
            c.rect(17, 10, 7, 1, p.deep)
            c.rect(8, 23, 16, 1, p.deep)
            // Lines of text
            c.rect(9, 13, 5, 1, p.brown)
            c.rect(9, 15, 6, 1, p.brown)
            c.rect(9, 17, 4, 1, p.brown)
            c.rect(9, 19, 5, 1, p.brown)
            c.rect(17, 13, 6, 1, p.brown)
            c.rect(17, 15, 4, 1, p.brown)
            c.rect(17, 17, 5, 1, p.brown)
            c.rect(17, 19, 3, 1, p.brown)
        }
    }
}

// MARK: - Parallax layers

private enum ParallaxArt {
    static let skyJMT = PixelSprite(width: 8, height: 8) { c in
        c.rect(0, 0, 8, 8, ArtPalette.sky)
    }

    /// Distant mountain silhouette — one tileable piece.
    /// Chosen heights are symmetric at the edges so tiles seam cleanly.
    static let mountainsJMT = PixelSprite(width: 256, height: 96) { c in
        let p = ArtPalette.self
        // Sky wash
        c.rect(0, 0, 256, 96, p.sky)
        // Horizon haze
        c.rect(0, 80, 256, 16, p.mountLight.opacity(0.4))

        // Generate jagged mountain silhouette
        var heights: [Int] = []
        // Seed a deterministic pattern using an array of control points, interpolated
        let control: [Int] = [22, 32, 46, 38, 54, 28, 44, 60, 48, 36, 52, 70, 56, 42, 50, 38, 22]
        // Tileable: first and last should match. Force last = first.
        var adjusted = control
        adjusted[adjusted.count - 1] = adjusted[0]
        let span = 256 / (adjusted.count - 1)
        for seg in 0..<(adjusted.count - 1) {
            let a = adjusted[seg]
            let b = adjusted[seg + 1]
            for i in 0..<span {
                let t = Double(i) / Double(span)
                let smooth = Double(a) * (1 - t) + Double(b) * t
                // Add a deterministic jaggedness
                let jag = (seg * 7 + i * 3) % 5 - 2
                heights.append(max(0, Int(smooth.rounded()) + jag))
            }
        }
        while heights.count < 256 { heights.append(heights.last ?? 0) }

        c.silhouette(heights: heights, baselineY: 95, color: p.mountBlue)

        // Second layer (darker back ridge behind)
        var back: [Int] = []
        for (i, h) in heights.enumerated() {
            back.append(h + (i * 3 % 6) - 8)
        }
        for (x, h) in back.enumerated() where h > 0 {
            let lo = max(0, 95 - h + 1)
            // Only the very tops of the back ridge peek above the front
            if lo < 95 - heights[x] {
                c.col(x, from: lo, to: 95 - heights[x], p.mountDark)
            }
        }

        // Snow caps on any column >= 52
        for (x, h) in heights.enumerated() where h >= 52 {
            c.px(x, 95 - h + 1, p.snow)
            if h >= 58 { c.px(x, 95 - h + 2, p.snow) }
            if h >= 64 { c.px(x, 95 - h + 3, p.snow) }
        }

        // Soft highlight on sunny faces (right-facing columns)
        for x in 1..<256 where heights[x] > 0 && heights[x] < heights[x - 1] {
            let top = 95 - heights[x] + 1
            c.px(x, top, p.mountLight)
        }
    }

    /// Closer rolling hills — shorter tile.
    static let hillsJMT = PixelSprite(width: 256, height: 64) { c in
        let p = ArtPalette.self

        // Generate rolling silhouette
        var heights: [Int] = []
        let control: [Int] = [18, 24, 30, 26, 32, 22, 28, 34, 28, 22, 26, 30, 20, 18]
        var adjusted = control
        adjusted[adjusted.count - 1] = adjusted[0]
        let span = 256 / (adjusted.count - 1)
        for seg in 0..<(adjusted.count - 1) {
            let a = adjusted[seg]
            let b = adjusted[seg + 1]
            let ad = Double(a)
            let bd = Double(b)
            for i in 0..<span {
                let t = Double(i) / Double(span)
                let lerp: Double = ad * (1.0 - t) + bd * t
                heights.append(Int(lerp.rounded()))
            }
        }
        while heights.count < 256 { heights.append(heights.last ?? 0) }

        c.silhouette(heights: heights, baselineY: 63, color: p.hillDark)

        // Lighter crowns
        for x in 0..<256 {
            let h = heights[x]
            if h > 0 {
                let top = 63 - h + 1
                c.col(x, from: top, to: top + max(1, h / 3), p.hillLight)
            }
        }

        // Scattered pine dots along the crown
        for x in stride(from: 4, to: 256, by: 9) {
            let h = heights[x]
            if h > 4 {
                let baseY = 63 - h
                c.rect(x, baseY - 3, 1, 3, p.treeDark)
                c.rect(x - 1, baseY - 2, 3, 1, p.green)
                c.rect(x - 1, baseY, 3, 1, p.green)
            }
        }
    }

    /// Ground strip — trail dirt for under the hiker.
    static let groundJMT = PixelSprite(width: 32, height: 16) { c in
        let p = ArtPalette.self
        c.rect(0, 0, 32, 16, p.sand)
        c.rect(0, 0, 32, 2, p.grassDark)
        c.rect(0, 2, 32, 1, p.grass)
        // Specks of gravel
        c.px(3, 7, p.stoneDark)
        c.px(10, 9, p.stoneDark)
        c.px(17, 6, p.stone)
        c.px(24, 11, p.stoneDark)
        c.px(29, 8, p.stone)
        c.px(6, 13, p.stoneDark)
        c.px(21, 14, p.stoneDark)
    }
}

// MARK: - Finale scene (512×320)

private enum FinaleArt {
    static let jmt = PixelSprite(width: 512, height: 320) { c in
        let p = ArtPalette.self

        // Sky gradient (sunrise bands, top to bottom: deep → sunrise → sun → sky)
        c.rect(0, 0, 512, 30, p.mountDark)
        c.rect(0, 30, 512, 30, p.sunrise)
        c.rect(0, 60, 512, 40, p.sun)
        c.rect(0, 100, 512, 80, p.sky)

        // Sun disc
        let sunX = 356
        let sunY = 80
        c.rect(sunX - 18, sunY - 18, 36, 36, p.sun)
        c.rect(sunX - 20, sunY - 14, 2, 28, p.sun)
        c.rect(sunX + 18, sunY - 14, 2, 28, p.sun)
        c.rect(sunX - 14, sunY - 20, 28, 2, p.sun)
        c.rect(sunX - 14, sunY + 18, 28, 2, p.sun)
        // Sun highlight
        c.rect(sunX - 14, sunY - 14, 28, 28, p.parchment)
        c.rect(sunX - 10, sunY - 10, 20, 20, p.sun)

        // Distant mountain ridge (far)
        var farHeights: [Int] = []
        for x in 0..<512 {
            let a = Double(x) * 0.035
            let noise: Double = 18.0 * sin(a) + 12.0 * sin(a * 1.7) + 6.0 * sin(a * 3.1)
            let h = 35 + Int(noise)
            farHeights.append(h)
        }
        c.silhouette(heights: farHeights, baselineY: 200, color: p.mountDark)
        for x in 0..<512 where farHeights[x] >= 50 {
            c.px(x, 200 - farHeights[x] + 1, p.snow)
            if farHeights[x] >= 60 {
                c.px(x, 200 - farHeights[x] + 2, p.snow)
            }
        }

        // Mid ridge
        var midHeights: [Int] = []
        for x in 0..<512 {
            let a = Double(x) * 0.025
            let noise: Double = 24.0 * sin(a * 0.8) + 16.0 * sin(a * 2.1) + 8.0 * sin(a * 4.3)
            let h = 55 + Int(noise)
            midHeights.append(h)
        }
        c.silhouette(heights: midHeights, baselineY: 230, color: p.mountBlue)
        for x in 0..<512 where midHeights[x] >= 72 {
            c.px(x, 230 - midHeights[x] + 1, p.snow)
        }

        // Mt. Whitney — the hero peak, towering center-left
        let whitneyBaseX = 220
        let peak: [Int] = [
            0, 4, 10, 18, 26, 34, 42, 50, 58, 66, 74, 82, 90, 98, 106, 114,
            122, 130, 138, 146, 154, 162, 170, 178, 186, 194, 202, 210, 218, 226, 234, 240,
            244, 248, 250, 252, 252, 250, 248, 244, 238, 232, 224, 216, 208, 198, 188, 176,
            164, 152, 140, 128, 116, 104, 92, 80, 68, 56, 44, 32, 22, 14, 8, 4
        ]
        let peakBaseY = 260
        for (i, h) in peak.enumerated() {
            let hh = h / 2  // scale for virtual 320-tall canvas
            c.col(whitneyBaseX + i, from: peakBaseY - hh, to: peakBaseY, p.stoneDark)
        }
        // Sunlit face
        for (i, h) in peak.enumerated() where i >= 28 {
            let hh = h / 2
            let top = peakBaseY - hh
            c.col(whitneyBaseX + i, from: top, to: top + hh / 3, p.stone)
        }
        // Snow cap
        for (i, h) in peak.enumerated() where h >= 200 {
            let top = peakBaseY - h / 2
            c.rect(whitneyBaseX + i, top, 1, 4, p.snow)
        }
        for (i, h) in peak.enumerated() where h >= 230 {
            let top = peakBaseY - h / 2
            c.rect(whitneyBaseX + i, top, 1, 7, p.snow)
        }

        // Clouds drifting high above
        cloud(c, x: 40, y: 50, w: 70, h: 8)
        cloud(c, x: 420, y: 40, w: 60, h: 7)
        cloud(c, x: 130, y: 30, w: 50, h: 6)

        // Foreground ridge and trail
        c.rect(0, 260, 512, 60, p.hillDark)
        c.rect(0, 258, 512, 3, p.hillLight)

        // Winding trail
        for x in 0..<512 {
            let wave: Double = 6.0 * sin(Double(x) * 0.04)
            let y = 285 + Int(wave)
            c.rect(x, y, 1, 3, p.sand)
            c.px(x, y - 1, p.grass)
        }

        // Hiker silhouette at summit, arms raised in triumph
        let hx = whitneyBaseX + 31       // centered on peak
        let hy = peakBaseY - peak[31] / 2 - 18   // just above peak top
        // Hat
        c.rect(hx - 2, hy, 4, 1, p.deep)
        c.rect(hx - 3, hy + 1, 6, 1, p.deep)
        // Head
        c.rect(hx - 1, hy + 2, 3, 2, p.skin)
        // Torso
        c.rect(hx - 2, hy + 4, 5, 6, p.coral)
        // Arms raised up
        c.rect(hx - 4, hy + 1, 1, 5, p.coral)
        c.rect(hx + 3, hy + 1, 1, 5, p.coral)
        c.px(hx - 4, hy, p.skin)
        c.px(hx + 3, hy, p.skin)
        // Legs
        c.rect(hx - 2, hy + 10, 2, 4, p.mountBlue)
        c.rect(hx + 1, hy + 10, 2, 4, p.mountBlue)
        // Boots
        c.rect(hx - 2, hy + 14, 2, 1, p.deep)
        c.rect(hx + 1, hy + 14, 2, 1, p.deep)

        // Summit marker next to hiker
        let mx = hx + 8
        let my = hy + 6
        c.rect(mx, my, 1, 10, p.brown)
        c.rect(mx + 1, my - 1, 6, 5, p.coral)

        // Small pines scattered in foreground
        for (fx, fy) in [(40, 300), (80, 305), (140, 302), (200, 308), (310, 304), (380, 306), (450, 302)] {
            c.rect(fx, fy - 8, 1, 8, p.treeDark)
            c.rect(fx - 3, fy - 6, 7, 2, p.green)
            c.rect(fx - 2, fy - 3, 5, 2, p.green)
            c.rect(fx - 1, fy - 1, 3, 1, p.green)
        }
    }

    private static func cloud(_ c: PixelCanvas, x: Int, y: Int, w: Int, h: Int) {
        let p = ArtPalette.self
        c.rect(x + 3, y, w - 6, h, p.parchment)
        c.rect(x, y + 1, 3, h - 2, p.parchment)
        c.rect(x + w - 3, y + 1, 3, h - 2, p.parchment)
        c.rect(x + 4, y - 1, w - 10, 1, p.parchment)
        // Shadow underside
        c.rect(x + 3, y + h - 1, w - 6, 1, p.cloudGray)
    }
}

// MARK: - Color helpers

private extension ArtPalette {
    static func forestGreen(opacity: Double) -> Color {
        Color(red: 0.357, green: 0.549, blue: 0.353).opacity(opacity)
    }
}
