import SwiftUI

/// Observable engine driving the immersive linear scene flow.
/// Single source of truth for scene-local time. Chapters consume `localTime(at:)`.
///
/// Pause is FIRST-CLASS: when `isPlaying` is false, `localTime(at:)` returns
/// the value it had when the user paused, frozen. Pressing play resumes from
/// where time stopped. The app launches paused so the very first scene
/// doesn't auto-scrub past its opening beats before the user gets oriented.
@MainActor
@Observable
final class SceneEngine {
    private(set) var currentGlobal: Int = 0
    private(set) var isPlaying: Bool = false

    /// Local time accumulated in the current scene from prior play sessions
    /// (i.e. the part of the scene the user has already watched). When the
    /// user is paused, this is the full localTime. When playing, the live
    /// delta from `playSessionStart` is added on top.
    private var accumulatedLocal: Double = 0
    /// Wall-clock reference when the current play session started; nil when
    /// paused. We anchor to `timeIntervalSinceReferenceDate` so the value
    /// survives system clock drift over the lifetime of one session.
    private var playSessionStart: Double? = nil

    var speed: Double = 1.0
    let totalScenes: Int

    /// Monotonic counter; incremented on every stopAutoAdvance() to invalidate in-flight asyncAfter blocks.
    private var advanceGeneration: Int = 0
    let sceneDuration: Double = 8.0

    /// Per-(chapter,scene) duration overrides. Ch01's 7 scenes are now
    /// windows of one continuous serial timeline (`Ch01Timeline`), so each
    /// scene's duration is the duration of its window. The total Ch01
    /// runtime at 1× ≈ 326 seconds — this is intentional pedagogical
    /// slo-mo; speed it up with `adjustSpeed`.
    private static let durationOverrides: [SceneAddress: Double] = [
        SceneAddress(chapter: 1, scene: 0): 69.0,   // Aaron writes α + sends to Ben
        SceneAddress(chapter: 1, scene: 1): 38.0,   // α to Carl
        SceneAddress(chapter: 1, scene: 2): 67.5,   // Ben writes β + sends to Aaron
        SceneAddress(chapter: 1, scene: 3): 33.0,   // Carl writes γ — asymmetry
        SceneAddress(chapter: 1, scene: 4): 37.0,   // γ to Aaron
        SceneAddress(chapter: 1, scene: 5): 37.5,   // β to Carl
        SceneAddress(chapter: 1, scene: 6): 44.5,   // γ to Ben + convergence
    ]

    /// Effective duration for the current scene, honoring overrides.
    func sceneDurationFor(_ address: SceneAddress) -> Double {
        Self.durationOverrides[address] ?? sceneDuration
    }

    var address: SceneAddress {
        SceneAddress.from(globalIndex: currentGlobal)
    }

    var currentChapter: ChapterDef {
        AllChapters.list[address.chapter]
    }

    /// Compute scene-local time at a given wall-clock date, honoring pause
    /// state. Speed scales the LIVE delta only — already-elapsed time is
    /// preserved at whatever speed it was clocked at.
    func localTime(at date: Date) -> Double {
        guard let start = playSessionStart else {
            return accumulatedLocal
        }
        let live = (date.timeIntervalSinceReferenceDate - start) * speed
        return max(0, accumulatedLocal + live)
    }

    /// Progress within current scene (0..1), capped at 1. Honors per-scene
    /// duration overrides so a long scene's progress bar doesn't max out
    /// after only 8 seconds.
    func progress(at date: Date) -> Double {
        min(1.0, localTime(at: date) / sceneDurationFor(address))
    }

    init() {
        self.totalScenes = AllChapters.totalScenes
        // Launch paused at t=0. The user sees a still title frame and
        // explicitly presses play (or the right arrow) to begin.
    }

    // MARK: - Navigation

    func next() {
        let wasPlaying = isPlaying
        stopAutoAdvance()
        if currentGlobal < totalScenes - 1 {
            currentGlobal += 1
            resetSceneTime(playing: wasPlaying)
            if wasPlaying { startAutoAdvance() }
        }
    }

    func previous() {
        let wasPlaying = isPlaying
        stopAutoAdvance()
        if currentGlobal > 0 {
            currentGlobal -= 1
            resetSceneTime(playing: wasPlaying)
            if wasPlaying { startAutoAdvance() }
        }
    }

    func goTo(global: Int) {
        let wasPlaying = isPlaying
        stopAutoAdvance()
        currentGlobal = max(0, min(global, totalScenes - 1))
        resetSceneTime(playing: wasPlaying)
        if wasPlaying { startAutoAdvance() }
    }

    func togglePlay() {
        if isPlaying {
            // Pausing: capture the live delta into the accumulator so the
            // next localTime() call returns exactly the frozen value.
            if let start = playSessionStart {
                let now = Date().timeIntervalSinceReferenceDate
                accumulatedLocal += (now - start) * speed
            }
            playSessionStart = nil
            isPlaying = false
            stopAutoAdvance()
        } else {
            // Resuming: anchor a new live delta from the current accumulator.
            playSessionStart = Date().timeIntervalSinceReferenceDate
            isPlaying = true
            startAutoAdvance()
        }
    }

    func adjustSpeed(delta: Double) {
        // Capture current localTime at the OLD speed before changing speed,
        // so the speed change doesn't retroactively scale already-elapsed time.
        if let start = playSessionStart {
            let now = Date().timeIntervalSinceReferenceDate
            accumulatedLocal += (now - start) * speed
            playSessionStart = now
        }
        speed = max(0.25, min(4.0, speed + delta))
        if isPlaying {
            stopAutoAdvance()
            startAutoAdvance()
        }
    }

    // MARK: - Internals

    /// Clear scene-local time. If the engine is currently in the playing
    /// state, anchor a fresh play session from now; otherwise leave it nil
    /// so the next localTime() call returns 0 cleanly.
    private func resetSceneTime(playing: Bool) {
        accumulatedLocal = 0
        playSessionStart = playing ? Date().timeIntervalSinceReferenceDate : nil
    }

    private func currentLocalTimeNow() -> Double {
        guard let start = playSessionStart else { return accumulatedLocal }
        let live = (Date().timeIntervalSinceReferenceDate - start) * speed
        return max(0, accumulatedLocal + live)
    }

    private func startAutoAdvance() {
        advanceGeneration += 1
        let myGen = advanceGeneration
        // Auto-advance fires after the REMAINING time in this scene (so a
        // pause→resume midway through Ch1.3 doesn't reset the 24s clock).
        let remaining = sceneDurationFor(address) - currentLocalTimeNow()
        let interval = max(0.05, remaining / max(0.1, speed))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, self.advanceGeneration == myGen, self.isPlaying else { return }
            if self.currentGlobal < self.totalScenes - 1 {
                self.currentGlobal += 1
                self.resetSceneTime(playing: true)
                self.startAutoAdvance()
            } else {
                self.isPlaying = false
                self.playSessionStart = nil
            }
        }
    }

    private func stopAutoAdvance() {
        // Invalidate any pending asyncAfter blocks.
        advanceGeneration += 1
    }
}
