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

    /// Wall-clock reference (Date.timeIntervalSinceReferenceDate) when this
    /// inspection began. Used to compute scene-local time for animation.
    private(set) var startReference: Double = 0

    var isActive: Bool { selectedDigest != nil }

    func select(_ digest: String) {
        selectedDigest = digest
        startReference = Date().timeIntervalSinceReferenceDate
    }

    func clear() {
        selectedDigest = nil
        startReference = 0
    }

    /// Inspection-local time in seconds since `select()`.
    func localTime(at date: Date) -> Double {
        guard startReference > 0 else { return 0 }
        return max(0, date.timeIntervalSinceReferenceDate - startReference)
    }
}
