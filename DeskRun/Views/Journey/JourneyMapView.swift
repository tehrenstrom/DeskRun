import SwiftUI

struct JourneyMapView: View {
    let appState: AppState

    private var active: JourneyState? { appState.journeyStore.active }
    private var trail: Trail? { appState.journeyEngine.currentTrail ?? (active.flatMap { TrailCatalog.trail(for: $0.trailID) }) }
    private var settings: AppSettings { appState.settings }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let trail, let active {
                mapScene(trail: trail, active: active)
            } else {
                Text("No active journey.")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(TrailColor.text.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Encounter banner
            if let encounter = appState.journeyEngine.pendingEncounter {
                EncounterBanner(
                    encounter: encounter,
                    onChoose: { choiceID in
                        appState.journeyEngine.resolve(choiceID: choiceID, wasDefault: false)
                    }
                )
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .frame(maxWidth: .infinity)
            } else if let resultText = appState.journeyEngine.lastResultText {
                EncounterResultToast(text: resultText) {
                    appState.journeyEngine.dismissResultText()
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }

            if let landmark = appState.journeyEngine.pendingLandmark {
                LandmarkNoticeView(landmark: landmark.landmark) {
                    appState.journeyEngine.dismissLandmarkNotice()
                }
                .padding(.top, 80)
                .transition(.scale.combined(with: .opacity))
                .frame(maxWidth: .infinity)
            }

            // Ambient wildlife/weather flavor caption (non-blocking, auto-dismiss).
            if appState.journeyEngine.pendingEncounter == nil,
               appState.journeyEngine.pendingLandmark == nil,
               let caption = appState.journeyEngine.ambientCaption {
                AmbientCaptionView(text: caption)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.journeyEngine.pendingEncounter?.id)
        .animation(.easeInOut(duration: 0.3), value: appState.journeyEngine.pendingLandmark?.id)
        .animation(.easeInOut(duration: 0.35), value: appState.journeyEngine.ambientCaption)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TrailColor.sky)
        .navigationTitle(trail?.name ?? "Trail")
    }

    @ViewBuilder
    private func mapScene(trail: Trail, active: JourneyState) -> some View {
        GeometryReader { geo in
            let pausedBannerHeight: CGFloat = active.isTrackingEnabled ? 0 : 32
            let walkCardHeight: CGFloat = 56
            VStack(spacing: 0) {
                if !active.isTrackingEnabled {
                    pausedBanner
                        .frame(height: pausedBannerHeight)
                }
                mapCanvas(trail: trail, active: active, width: geo.size.width)
                    .frame(height: max(120, geo.size.height - walkCardHeight - 120 - pausedBannerHeight))

                JourneyWalkCard(appState: appState)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(height: walkCardHeight)

                StatsBar(state: active, trail: trail, speed: appState.treadmillState.currentSpeed, settings: settings)
                    .frame(height: 120)
            }
        }
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(TrailColor.forestGreen)
            Text("JOURNEY PAUSED — RESUME FROM SETTINGS › ADVENTURE MODE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(TrailColor.darkEarth)
                .tracking(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(TrailColor.forestGreen.opacity(0.2))
    }

    @ViewBuilder
    private func mapCanvas(trail: Trail, active: JourneyState, width: CGFloat) -> some View {
        let pxPerMile: CGFloat = 80
        let hikerOffsetX: CGFloat = width * 0.3
        let speedKmh = appState.treadmillState.currentSpeed

        GeometryReader { geo in
            let fullHeight = geo.size.height
            let trailRibbonH: CGFloat = 24
            let hillsH: CGFloat = 96
            let mountainsH: CGFloat = 140
            let trailTopY = fullHeight - trailRibbonH
            let hikerSize: CGFloat = 64
            let landmarkSize: CGFloat = 72

            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                let trailID = trail.id
                let isTracking = active.isTrackingEnabled
                // Band frames for ambient encounters. All in this ZStack's coord space.
                let skyBand = CGRect(
                    x: 0, y: 4,
                    width: geo.size.width,
                    height: max(40, trailTopY - hillsH - mountainsH / 2 - 4)
                )
                let distanceBand = CGRect(
                    x: 0, y: trailTopY - hillsH + 8,
                    width: geo.size.width,
                    height: max(24, hillsH * 0.55)
                )
                let foregroundBand = CGRect(
                    x: 0, y: trailTopY - 54,
                    width: geo.size.width,
                    height: 54
                )

                ZStack(alignment: .topLeading) {
                    // Sky background
                    TrailColor.sky
                        .frame(width: geo.size.width, height: fullHeight)

                    // Parallax mountains — bottom edge just above the hills for overlap
                    ParallaxLayer(
                        assetName: trail.mapArt.mountainAsset,
                        width: 512,
                        height: mountainsH,
                        scrollOffset: CGFloat(active.milesTraveled) * pxPerMile * 0.3,
                        fallbackColor: TrailColor.mountainBlue.opacity(0.6)
                    )
                    .frame(width: geo.size.width, height: mountainsH)
                    .offset(y: trailTopY - hillsH - mountainsH + 24)

                    // Ambient sky band — clouds, birds, eagles, weather sheets.
                    AmbientEncounterLayer(
                        band: .sky,
                        trailID: trailID,
                        milesTraveled: active.milesTraveled,
                        speedKmh: speedKmh,
                        isTrackingEnabled: isTracking,
                        date: timeline.date,
                        bandFrame: skyBand,
                        hikerScreenX: hikerOffsetX,
                        pxPerMile: pxPerMile,
                        onNotableSpawn: { species in
                            appState.journeyEngine.showAmbientCaption(species.caption)
                        }
                    )

                    // Parallax hills — bottom edge sits on the trail top
                    ParallaxLayer(
                        assetName: trail.mapArt.hillAsset,
                        width: 512,
                        height: hillsH,
                        scrollOffset: CGFloat(active.milesTraveled) * pxPerMile * 0.6,
                        fallbackColor: TrailColor.forestGreen.opacity(0.6)
                    )
                    .frame(width: geo.size.width, height: hillsH)
                    .offset(y: trailTopY - hillsH)

                    // Ambient distance band — far-off hikers, bears, ravens atop the hills.
                    AmbientEncounterLayer(
                        band: .distance,
                        trailID: trailID,
                        milesTraveled: active.milesTraveled,
                        speedKmh: speedKmh,
                        isTrackingEnabled: isTracking,
                        date: timeline.date,
                        bandFrame: distanceBand,
                        hikerScreenX: hikerOffsetX,
                        pxPerMile: pxPerMile,
                        onNotableSpawn: { species in
                            appState.journeyEngine.showAmbientCaption(species.caption)
                        }
                    )

                    // Trail ribbon (the ground line)
                    Rectangle()
                        .fill(TrailColor.desertSand)
                        .frame(width: geo.size.width, height: trailRibbonH)
                        .overlay(
                            Rectangle()
                                .fill(TrailColor.darkEarth.opacity(0.2))
                                .frame(height: 2)
                                .offset(y: 11)
                        )
                        .offset(y: trailTopY)

                    // Landmarks, feet planted on the trail
                    ForEach(trail.landmarks) { landmark in
                        let worldOffset = (landmark.mileMarker - active.milesTraveled) * Double(pxPerMile)
                        let screenX = hikerOffsetX + CGFloat(worldOffset)
                        if screenX > -100 && screenX < width + 100 {
                            LandmarkSprite(
                                landmark: landmark,
                                highlighted: active.visitedLandmarkIDs.contains(landmark.id)
                            )
                            .frame(width: landmarkSize, height: landmarkSize + 22, alignment: .bottom)
                            .position(x: screenX, y: trailTopY - (landmarkSize + 22) / 2 + 2)
                        }
                    }

                    // Ambient foreground band — marmots, deer, squirrels passing by the trail.
                    AmbientEncounterLayer(
                        band: .foreground,
                        trailID: trailID,
                        milesTraveled: active.milesTraveled,
                        speedKmh: speedKmh,
                        isTrackingEnabled: isTracking,
                        date: timeline.date,
                        bandFrame: foregroundBand,
                        hikerScreenX: hikerOffsetX,
                        pxPerMile: pxPerMile,
                        onNotableSpawn: { species in
                            appState.journeyEngine.showAmbientCaption(species.caption)
                        }
                    )

                    // Trail signposts — wooden boards listing upcoming landmark
                    // distances, sparse (~1 every 20mi), world-locked.
                    TrailSignpostLayer(
                        trail: trail,
                        milesTraveled: active.milesTraveled,
                        bandFrame: foregroundBand,
                        hikerScreenX: hikerOffsetX,
                        pxPerMile: pxPerMile,
                        settings: settings
                    )

                    // Hiker — bottom of sprite rests on the trail top
                    HikerSprite(size: hikerSize, date: timeline.date, speedKmh: speedKmh)
                        .frame(width: hikerSize, height: hikerSize)
                        .position(x: hikerOffsetX, y: trailTopY - hikerSize / 2 + 4)

                }
            }
        }
    }
}

// MARK: - Stats Bar

private struct StatsBar: View {
    let state: JourneyState
    let trail: Trail
    let speed: Double
    let settings: AppSettings

    @State private var hoveredLandmarkID: String?

    var body: some View {
        VStack(spacing: 8) {
            JourneyProgressBar(
                progress: state.progressPercentage,
                trail: trail,
                visitedLandmarkIDs: state.visitedLandmarkIDs,
                height: 12,
                hoveredLandmarkID: $hoveredLandmarkID
            )
            HStack(alignment: .top, spacing: 18) {
                stat(label: settings.useMetric ? "KM" : "MILES", value: settings.distanceValueString(miles: state.milesTraveled))
                stat(label: "REMAINING", value: settings.distanceValueString(miles: max(0, trail.totalMiles - state.milesTraveled), decimals: 0))
                stat(label: "MORALE", value: "\(state.morale)", tint: moraleColor(state.morale))
                stat(label: "ENERGY", value: "\(state.energy)", tint: energyColor(state.energy))
                stat(label: "SPEED", value: settings.speedString(speed))
                if let target = state.targetCompletionDate {
                    stat(label: "TARGET", value: shortDate(target), tint: state.isOverdue ? TrailColor.coral : TrailColor.text)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(TrailColor.parchment)
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundStyle(TrailColor.darkEarth),
            alignment: .top
        )
        // Tooltip overlay applied AFTER the border so it stacks above the 2 px
        // darkEarth line and can float freely into the map canvas above.
        .overlay(alignment: .topLeading) {
            if let id = hoveredLandmarkID,
               let landmark = trail.landmarks.first(where: { $0.id == id }) {
                GeometryReader { geo in
                    let innerWidth = geo.size.width - 32     // -padding(.horizontal, 16)
                    let fraction = min(1.0, landmark.mileMarker / trail.totalMiles)
                    let x = 16 + innerWidth * CGFloat(fraction)
                    tooltipView(for: landmark)
                        .fixedSize()
                        .position(x: clampTooltipX(x, width: geo.size.width), y: -14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.08), value: hoveredLandmarkID)
            }
        }
    }

    private func tooltipView(for landmark: Landmark) -> some View {
        Text(tooltipText(for: landmark))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(TrailColor.darkEarth)
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TrailColor.parchment)
            .overlay(
                Rectangle()
                    .strokeBorder(TrailColor.darkEarth, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    private func tooltipText(for landmark: Landmark) -> String {
        let delta = landmark.mileMarker - state.milesTraveled
        if state.visitedLandmarkIDs.contains(landmark.id) {
            return "\(landmark.name.uppercased()) · VISITED"
        }
        if delta > 0 {
            return "\(landmark.name.uppercased()) · \(settings.distanceString(miles: delta, decimals: 1)) AHEAD"
        }
        return landmark.name.uppercased()
    }

    private func clampTooltipX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let pad: CGFloat = 90
        return max(pad, min(width - pad, x))
    }

    private func stat(label: String, value: String, tint: Color = TrailColor.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(TrailColor.text.opacity(0.55))
                .tracking(1)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private func moraleColor(_ m: Int) -> Color {
        if m >= 75 { return TrailColor.forestGreen }
        if m >= 40 { return TrailColor.text }
        return TrailColor.coral
    }

    private func energyColor(_ e: Int) -> Color {
        if e >= 50 { return TrailColor.forestGreen }
        if e >= 20 { return TrailColor.desertSand }
        return TrailColor.coral
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - Ambient Caption

private struct AmbientCaptionView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(TrailColor.forestGreen.opacity(0.8))
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(TrailColor.text.opacity(0.85))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(TrailColor.parchment.opacity(0.85))
        .overlay(
            Rectangle()
                .strokeBorder(TrailColor.darkEarth.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }
}

// MARK: - Encounter Result Toast

private struct EncounterResultToast: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkle")
                .foregroundStyle(TrailColor.forestGreen)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(TrailColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("OK") { onDismiss() }
                .buttonStyle(RetroSecondaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(TrailColor.parchment)
        .overlay(
            Rectangle()
                .strokeBorder(TrailColor.forestGreen, lineWidth: 2)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - Landmark Notice

private struct LandmarkNoticeView: View {
    let landmark: Landmark
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("LANDMARK REACHED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(TrailColor.coral)
                .tracking(2)

            PixelImage(assetName: landmark.spriteAsset, size: 96)

            Text(landmark.name.uppercased())
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundStyle(TrailColor.darkEarth)
                .tracking(2)

            Text(landmark.flavorText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(TrailColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            Button("Continue") { onDismiss() }
                .buttonStyle(RetroButtonStyle(tint: TrailColor.forestGreen))
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .background(TrailColor.parchment)
        .overlay(
            Rectangle()
                .strokeBorder(TrailColor.darkEarth, lineWidth: 3)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

// MARK: - Journey Progress Bar with landmark ticks

private struct JourneyProgressBar: View {
    let progress: Double
    let trail: Trail
    let visitedLandmarkIDs: Set<String>
    let height: CGFloat
    @Binding var hoveredLandmarkID: String?

    var body: some View {
        VStack(spacing: 2) {
            // Landmark markers above the bar
            GeometryReader { geo in
                ForEach(trail.landmarks) { landmark in
                    let fraction = min(1.0, landmark.mileMarker / trail.totalMiles)
                    let x = geo.size.width * CGFloat(fraction)
                    landmarkMarker(for: landmark)
                        .position(x: x, y: 7)
                }
            }
            .frame(height: 14)

            // Progress bar itself
            RetroProgressBar(
                progress: progress,
                fillColor: TrailColor.forestGreen,
                height: height
            )
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    ForEach(trail.landmarks) { landmark in
                        let fraction = min(1.0, landmark.mileMarker / trail.totalMiles)
                        let x = geo.size.width * CGFloat(fraction)
                        Rectangle()
                            .fill(tickOnBarColor(for: landmark, atFraction: fraction))
                            .frame(width: landmark.isMajor ? 2 : 1, height: height - 4)
                            .position(x: x, y: height / 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func landmarkMarker(for landmark: Landmark) -> some View {
        let visited = visitedLandmarkIDs.contains(landmark.id)
        let symbol = landmark.isMajor ? "★" : "▼"
        let color: Color = visited
            ? (landmark.isMajor ? TrailColor.coral : TrailColor.forestGreen)
            : TrailColor.darkEarth.opacity(0.35)
        Text(symbol)
            .font(.system(size: landmark.isMajor ? 12 : 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 24, height: 16)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredLandmarkID = landmark.id
                } else if hoveredLandmarkID == landmark.id {
                    hoveredLandmarkID = nil
                }
            }
    }

    /// A thin vertical tick drawn ON the bar at the landmark's position.
    /// Uses a contrasting colour depending on whether the fill has reached it.
    private func tickOnBarColor(for landmark: Landmark, atFraction: Double) -> Color {
        let reached = progress >= atFraction
        if visitedLandmarkIDs.contains(landmark.id) {
            return reached ? TrailColor.parchment : TrailColor.coral
        }
        return TrailColor.darkEarth.opacity(reached ? 0.6 : 0.4)
    }
}
