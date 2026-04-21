import SwiftUI

/// Renders active trail signposts for the current journey, world-locked to
/// the hiker's position. Parallel to `AmbientEncounterLayer` but with its own
/// scheduler since sign contents are composed of real text (not pixel art).
///
/// Insert between the foreground ambient band and the hiker sprite so signs
/// stand at the trail ribbon and pass behind the hiker with a fade dead-zone.
struct TrailSignpostLayer: View {
    let trail: Trail
    let milesTraveled: Double
    let bandFrame: CGRect
    let hikerScreenX: CGFloat
    let pxPerMile: CGFloat
    let settings: AppSettings

    var body: some View {
        let renders = TrailSignpostScheduler.activeSigns(
            trail: trail,
            milesTraveled: milesTraveled,
            hikerScreenX: hikerScreenX,
            pxPerMile: pxPerMile,
            bandBottomY: bandFrame.maxY,
            bandWidth: bandFrame.width
        )

        ZStack(alignment: .topLeading) {
            ForEach(renders) { r in
                TrailSignpostView(sign: r.sign, settings: settings)
                    .frame(width: TrailSignpostView.viewSize.width,
                           height: TrailSignpostView.viewSize.height)
                    .opacity(r.opacity)
                    .position(
                        x: r.x,
                        y: r.footY - TrailSignpostView.viewSize.height / 2
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
