import SwiftUI

/// Observable state for the vertex-inspection overlay.
///
/// When a user clicks a vertex in Ch02 the chapter calls `select(_:)`. The
/// `ImmersiveView` watches `selectedDigest` and renders `VertexInspector` on
/// top of the canvas. The inspector reads `localTime(at:)` to drive the
/// recursive reveal animation (each ancestor depth level uncovers in turn).
@MainActor
@Observable
final class InspectionState {
    /// Digest of the vertex the user clicked. `nil` ⇒ inspector hidden.
    private(set) var selectedDigest: String? = nil

    /// Optional second vertex for side-by-side comparison mode. When set, the
    /// inspector renders both ancestor cones with shared/divergent coloring,
    /// teaching how identical local order experience emerges from different
    /// observation points.
    private(set) var compareDigest: String? = nil

    /// Wall-clock reference (Date.timeIntervalSinceReferenceDate) when this
    /// inspection began. Used to compute scene-local time for animation.
    private(set) var startReference: Double = 0

    var isActive: Bool { selectedDigest != nil }
    var isComparing: Bool { selectedDigest != nil && compareDigest != nil }

    func select(_ digest: String) {
        selectedDigest = digest
        compareDigest = nil
        startReference = Date().timeIntervalSinceReferenceDate
    }

    /// Add a second vertex for comparison. Only valid when an initial vertex
    /// is already selected; restarts the animation timer so the recursive
    /// reveal plays out fresh in two-pane mode.
    func setCompare(_ digest: String) {
        guard selectedDigest != nil, digest != selectedDigest else { return }
        compareDigest = digest
        startReference = Date().timeIntervalSinceReferenceDate
    }

    func clearCompare() {
        compareDigest = nil
        convergenceStartReference = 0
        startReference = Date().timeIntervalSinceReferenceDate
    }

    func clear() {
        selectedDigest = nil
        compareDigest = nil
        convergenceStartReference = 0
        startReference = 0
    }

    /// Inspection-local time in seconds since `select()`.
    func localTime(at date: Date) -> Double {
        guard startReference > 0 else { return 0 }
        return max(0, date.timeIntervalSinceReferenceDate - startReference)
    }

    // MARK: - Convergence playback ("snap-together")

    /// When > 0, the side-by-side comparison enters playback mode: A-only and
    /// B-only ancestor cards drift toward the divider, fade, and a teal
    /// "TOTAL ORDER ESTABLISHED" stamp blooms at the convergence round.
    /// Strictly additive — does not alter the static comparison rendering.
    private(set) var convergenceStartReference: Double = 0
    var isPlayingConvergence: Bool { convergenceStartReference > 0 }

    func playConvergence() {
        guard isComparing else { return }
        convergenceStartReference = Date().timeIntervalSinceReferenceDate
    }

    func stopConvergence() {
        convergenceStartReference = 0
    }

    /// Seconds since `playConvergence()` was called. 0 if not playing.
    func convergenceTime(at date: Date) -> Double {
        guard convergenceStartReference > 0 else { return 0 }
        return max(0, date.timeIntervalSinceReferenceDate - convergenceStartReference)
    }
}
