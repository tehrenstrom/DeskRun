import SwiftUI

/// A single rendered trail signpost: a wooden board listing upcoming
/// landmarks and their distances, on a post whose foot rests on the trail
/// ribbon. The board is a composite SwiftUI view (shapes + text) rather than
/// a flat `PixelImage`, because the waypoint rows need real text layout.
///
/// Fixed logical size: 96 × 64 pt. Board width is 88pt; board height grows
/// with waypoint count and the post stem takes whatever's left.
struct TrailSignpostView: View {
    let sign: TrailSignpost
    let settings: AppSettings

    /// Outer view size — chosen to fit 2–3 plank rows plus post stem.
    static let viewSize = CGSize(width: 96, height: 64)

    private static let boardWidth: CGFloat = 88
    private static let rowHeight: CGFloat = 12
    private static let boardTopPadding: CGFloat = 5
    private static let boardBottomPadding: CGFloat = 4
    private static let postWidth: CGFloat = 5
    private static let rowTextInset: CGFloat = 5

    private var boardHeight: CGFloat {
        Self.boardTopPadding
            + Self.boardBottomPadding
            + CGFloat(sign.waypoints.count) * Self.rowHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Post stem — behind the board, runs from board bottom to view bottom.
            VStack(spacing: 0) {
                Spacer(minLength: 0).frame(height: boardHeight - 1)
                postStem
            }

            board
        }
        .frame(width: Self.viewSize.width, height: Self.viewSize.height)
        // Subtle drop shadow grounds the sign without fighting the pixel aesthetic.
        .shadow(color: .black.opacity(0.20), radius: 1.5, x: 0, y: 1)
    }

    // MARK: - Board

    private var board: some View {
        ZStack {
            Rectangle()
                .fill(ArtPalette.paperYellow)
                .frame(width: Self.boardWidth, height: boardHeight)

            // 1pt top highlight, 1pt bottom shadow — mimics the
            // rim/shadow treatment used by AmbientArt sprites.
            VStack(spacing: 0) {
                Rectangle().fill(ArtPalette.sand).frame(height: 1)
                Spacer(minLength: 0)
                Rectangle().fill(ArtPalette.deep).frame(height: 1)
            }
            .frame(width: Self.boardWidth, height: boardHeight)

            // 1pt left/right edge — darker rim.
            HStack(spacing: 0) {
                Rectangle().fill(ArtPalette.brown).frame(width: 1)
                Spacer(minLength: 0)
                Rectangle().fill(ArtPalette.brown).frame(width: 1)
            }
            .frame(width: Self.boardWidth, height: boardHeight)

            // Waypoint rows.
            VStack(spacing: 0) {
                Spacer(minLength: 0).frame(height: Self.boardTopPadding)
                ForEach(Array(sign.waypoints.enumerated()), id: \.offset) { idx, wp in
                    row(wp: wp, showSeparator: idx < sign.waypoints.count - 1)
                }
                Spacer(minLength: 0).frame(height: Self.boardBottomPadding)
            }
            .frame(width: Self.boardWidth, height: boardHeight, alignment: .top)
        }
        .frame(width: Self.boardWidth, height: boardHeight, alignment: .top)
    }

    @ViewBuilder
    private func row(wp: SignWaypoint, showSeparator: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Text(shortName(wp.name))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text(settings.distanceValueString(miles: wp.milesAway))
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(ArtPalette.deep)
            .tracking(0.5)
            .padding(.horizontal, Self.rowTextInset)
            .frame(height: Self.rowHeight - (showSeparator ? 1 : 0))

            if showSeparator {
                Rectangle()
                    .fill(ArtPalette.brown.opacity(0.35))
                    .frame(height: 1)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: Self.boardWidth, height: Self.rowHeight)
    }

    // MARK: - Post

    private var postStem: some View {
        Rectangle()
            .fill(ArtPalette.brown)
            .frame(width: Self.postWidth)
            .overlay(alignment: .leading) {
                // 1pt shadow on the left face of the post.
                Rectangle()
                    .fill(ArtPalette.deep)
                    .frame(width: 1)
            }
    }

    // MARK: - Name shortening

    /// Trail signs in the wild abbreviate. Strip common redundant suffixes
    /// and uppercase. Anything still too long is tail-truncated by the Text
    /// view itself — the plank width is the authoritative guard.
    private func shortName(_ name: String) -> String {
        var s = name.uppercased()
        let replacements: [(String, String)] = [
            (" SUMMIT", ""),
            (" MEADOWS", ""),
            (" ISLAND LAKE", " ISLE"),
            (" PEAK", " PK"),
            ("MT. ", "MT "),
            ("MOUNT ", "MT ")
        ]
        for (needle, rep) in replacements {
            s = s.replacingOccurrences(of: needle, with: rep)
        }
        return s
    }
}
