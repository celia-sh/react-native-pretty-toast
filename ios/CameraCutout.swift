import SwiftUI

/// The camera cutout the pill morphs out of.
enum CameraCutout {
    case dynamicIsland
    /// A camera hole in the screen, in points, in portrait.
    case holePunch(CGRect)

    /// Screens with a camera hole that UIKit does not describe publicly, keyed by
    /// model identifier: each entry is a screen's portrait size and the hole in it.
    /// A listed model is authoritative, so its other screens have no cutout — the
    /// iPhone Duo's inner display has an under-display camera, and its 82pt top
    /// inset would otherwise read as a Dynamic Island.
    private static let holePunches: [String: [(screen: CGSize, hole: CGRect)]] = [
        // iPhone Duo cover display. Measured from the display mask at 3x; the
        // private `_exclusionArea` rounds it to {399, 30, 37, 37}, which leaves the
        // collapsed pill peeking out of the camera.
        "iPhone19,4": [
            (CGSize(width: 466, height: 678), CGRect(x: 1199.0 / 3, y: 88.0 / 3, width: 37, height: 37)),
        ],
    ]

    /// The hole in a listed screen; in portrait only, so other orientations
    /// slide in.
    static func holePunch(screenSize: CGSize) -> CGRect? {
        holePunches[modelIdentifier]?.first { $0.screen == screenSize }?.hole
    }

    static func hasDynamicIsland(safeAreaTop: CGFloat) -> Bool {
        holePunches[modelIdentifier] == nil && safeAreaTop >= 59
    }

    private static let modelIdentifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()
}

/// Where the pill collapses to and how it and its content are laid out when
/// expanded. Offsets are from the top center of the window.
struct PillGeometry {
    let morphsFromCutout: Bool
    let collapsedSize: CGSize
    let collapsedOffset: CGSize
    let expandedOffset: CGSize
    let expandedWidth: CGFloat
    let baseHeight: CGFloat
    /// Height available to short content before the pill has to grow.
    let baseContentArea: CGFloat
    let contentInsets: EdgeInsets
    /// Circular corner radii for a hole punch, collapsed and expanded.
    let holeCornerRadius: (collapsed: CGFloat, expanded: CGFloat)?

    /// `size` is the whole window for a hole punch.
    init(cutout: CameraCutout?, size: CGSize, safeAreaTop: CGFloat) {
        let topOffset: CGFloat = 11 + max(safeAreaTop - 59, 0)
        switch cutout {
        case .dynamicIsland:
            let islandHeight: CGFloat = 36
            morphsFromCutout = true
            holeCornerRadius = nil
            collapsedSize = CGSize(width: 120, height: islandHeight)
            collapsedOffset = CGSize(width: 0, height: topOffset)
            // Nudge up 0.5pt so the centered stroke clears the DI's top line
            // instead of sitting half-behind it.
            expandedOffset = CGSize(width: 0, height: topOffset - 0.5)
            expandedWidth = size.width - (topOffset * 2)
            baseHeight = 90
            // Reserve the island band at the top so the content is always laid
            // out in the visible area beneath it.
            contentInsets = EdgeInsets(top: islandHeight, leading: 0, bottom: 12, trailing: 0)
            baseContentArea = baseHeight - islandHeight - 12
        case .holePunch(let hole):
            baseHeight = 70
            // A one-row pill is a capsule; the hole sits concentric with its end
            // cap, and the content keeps clear of it on that side instead of
            // under it, so the pill keeps the compact height. Taller content
            // grows the pill downward.
            let ring = (baseHeight / 2) - (hole.width / 2)
            let margin = min(hole.minX, size.width - hole.maxX) - ring
            // The row pads itself by 20pt; leave 6pt between it and the hole.
            let clearance = (hole.width + ring) + 6 - 20
            let trailing = hole.midX > size.width / 2
            // Collapse a point inside the hole so the antialiased edge and the
            // fading stroke end up under the camera.
            let collapsed = hole.insetBy(dx: 1, dy: 1)
            morphsFromCutout = true
            holeCornerRadius = (collapsed.width / 2, baseHeight / 2)
            collapsedSize = collapsed.size
            collapsedOffset = CGSize(width: collapsed.midX - (size.width / 2), height: collapsed.minY)
            expandedOffset = CGSize(width: 0, height: hole.minY - ring)
            expandedWidth = size.width - (margin * 2)
            contentInsets = EdgeInsets(
                top: 0,
                leading: trailing ? 0 : clearance,
                bottom: 0,
                trailing: trailing ? clearance : 0
            )
            baseContentArea = baseHeight - 20
        case nil:
            morphsFromCutout = false
            holeCornerRadius = nil
            collapsedSize = CGSize(width: 120, height: 36)
            collapsedOffset = .zero
            expandedOffset = .zero
            expandedWidth = size.width - (topOffset * 2)
            baseHeight = 70
            contentInsets = EdgeInsets()
            baseContentArea = baseHeight - 20
        }
    }
}
