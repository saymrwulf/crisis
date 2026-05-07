import SwiftUI

/// Observable engine driving the immersive linear scene flow.
/// Single source of truth for scene-local time. Chapters consume `localTime(at:)`.
///
/// Time is FIRST-CLASS:
///
///   - `isPlaying` toggles wall-clock advance.
///   - `speed` is SIGNED. Positive = forward, negative = reverse,
///     `0` = paused (regardless of `isPlaying`). Range −16…+16.
///   - `chapterPosition(at:)` and `setChapterPosition(_:)` give the user
///     a "master of time" handle: scrub freely to any point in the
///     current chapter's continuous timeline, in either direction.
///   - The app launches paused so the very first scene doesn't auto-scrub
///     past its opening beats before the viewer gets oriented.
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

    /// Signed playback speed. Negative values play in reverse; 0 freezes
    /// time even if `isPlaying` is true. Clamped to [−16, +16].
    var speed: Double = 1.0
    let totalScenes: Int

    /// Speed range exposed to the UI (signed, log-friendly).
    static let speedMin: Double = -16
    static let speedMax: Double = 16

    /// Monotonic counter; incremented on every stopAutoAdvance() to invalidate in-flight asyncAfter blocks.
    private var advanceGeneration: Int = 0
    let sceneDuration: Double = 8.0

    /// Per-(chapter,scene) duration overrides. Ch01's 7 scenes are now
    /// windows of one continuous serial timeline (`Ch01Timeline`), so each
    /// scene's duration is the duration of its window. The total Ch01
    /// runtime at 1× ≈ 326 seconds — this is intentional pedagogical
    /// slo-mo; speed it up with the speed slider.
    private static let durationOverrides: [SceneAddress: Double] = [
        // Ch00 — opener (3 scenes mapping to Ch00Timeline windows)
        SceneAddress(chapter: 0, scene: 0): 16.0,
        SceneAddress(chapter: 0, scene: 1): 14.0,
        SceneAddress(chapter: 0, scene: 2): 13.5,
        // Ch01 — gossip story (7 scenes mapping to Ch01Timeline windows)
        SceneAddress(chapter: 1, scene: 0): 69.0,
        SceneAddress(chapter: 1, scene: 1): 38.0,
        SceneAddress(chapter: 1, scene: 2): 67.5,
        SceneAddress(chapter: 1, scene: 3): 33.0,
        SceneAddress(chapter: 1, scene: 4): 37.0,
        SceneAddress(chapter: 1, scene: 5): 37.5,
        SceneAddress(chapter: 1, scene: 6): 44.5,
        // Ch02 — partition (4 scenes mapping to Ch02Timeline windows)
        SceneAddress(chapter: 2, scene: 0): 14.0,
        SceneAddress(chapter: 2, scene: 1): 35.0,
        SceneAddress(chapter: 2, scene: 2): 22.5,
        SceneAddress(chapter: 2, scene: 3): 44.0,
        // Ch03 — rounds (3 scenes mapping to Ch03Timeline windows)
        SceneAddress(chapter: 3, scene: 0): 23.5,
        SceneAddress(chapter: 3, scene: 1): 20.5,
        SceneAddress(chapter: 3, scene: 2): 28.0,
        // Ch04 — voting (3 scenes mapping to Ch04Timeline windows)
        SceneAddress(chapter: 4, scene: 0): 16.0,
        SceneAddress(chapter: 4, scene: 1): 23.5,
        SceneAddress(chapter: 4, scene: 2): 23.0,
        // Ch05 — leader (2 scenes)
        SceneAddress(chapter: 5, scene: 0): 29.0,
        SceneAddress(chapter: 5, scene: 1): 18.5,
        // Ch09 — Byzantine (2 scenes mapping to Ch09Timeline windows)
        SceneAddress(chapter: 9, scene: 0): 47.5,
        SceneAddress(chapter: 9, scene: 1): 32.0,
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
    /// state and signed speed. localTime is clamped to [0, sceneDuration].
    func localTime(at date: Date) -> Double {
        guard let start = playSessionStart else {
            return accumulatedLocal
        }
        let live = (date.timeIntervalSinceReferenceDate - start) * speed
        let dur = sceneDurationFor(address)
        return max(0, min(dur, accumulatedLocal + live))
    }

    /// Progress within current scene (0..1), capped at 1.
    func progress(at date: Date) -> Double {
        min(1.0, localTime(at: date) / sceneDurationFor(address))
    }

    init() {
        self.totalScenes = AllChapters.totalScenes
        // Launch paused at t=0.
    }

    // MARK: - Chapter-level position (the slider's territory)

    /// Total duration of the current chapter's timeline at 1× speed —
    /// the sum of all its scenes' durations.
    var currentChapterDuration: Double {
        var t: Double = 0
        for s in 0..<currentChapter.sceneCount {
            t += sceneDurationFor(SceneAddress(chapter: address.chapter, scene: s))
        }
        return t
    }

    /// Position within the current chapter's timeline (0..currentChapterDuration).
    func chapterPosition(at date: Date) -> Double {
        var t: Double = 0
        for s in 0..<address.scene {
            t += sceneDurationFor(SceneAddress(chapter: address.chapter, scene: s))
        }
        return t + localTime(at: date)
    }

    /// Seek to an arbitrary point in the current chapter's timeline.
    /// Resolves which scene that point falls in and updates accumulatedLocal.
    /// Preserves `isPlaying` and `speed`.
    func setChapterPosition(_ position: Double) {
        let clamped = max(0, min(currentChapterDuration, position))
        var remaining = clamped
        let chapter = address.chapter
        for s in 0..<currentChapter.sceneCount {
            let dur = sceneDurationFor(SceneAddress(chapter: chapter, scene: s))
            if remaining <= dur || s == currentChapter.sceneCount - 1 {
                let target = SceneAddress(chapter: chapter, scene: s)
                currentGlobal = target.globalIndex
                accumulatedLocal = remaining
                playSessionStart = isPlaying ? Date().timeIntervalSinceReferenceDate : nil
                stopAutoAdvance()
                if isPlaying { startAutoAdvance() }
                return
            }
            remaining -= dur
        }
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
            if let start = playSessionStart {
                let now = Date().timeIntervalSinceReferenceDate
                accumulatedLocal += (now - start) * speed
                let dur = sceneDurationFor(address)
                accumulatedLocal = max(0, min(dur, accumulatedLocal))
            }
            playSessionStart = nil
            isPlaying = false
            stopAutoAdvance()
        } else {
            playSessionStart = Date().timeIntervalSinceReferenceDate
            isPlaying = true
            startAutoAdvance()
        }
    }

    /// Set absolute speed. Captures whatever localTime the engine had at
    /// the OLD speed so a speed change doesn't retroactively rescale the
    /// time already elapsed.
    func setSpeed(_ s: Double) {
        let now = Date().timeIntervalSinceReferenceDate
        if let start = playSessionStart {
            accumulatedLocal += (now - start) * speed
            let dur = sceneDurationFor(address)
            accumulatedLocal = max(0, min(dur, accumulatedLocal))
            playSessionStart = now
        }
        speed = max(Self.speedMin, min(Self.speedMax, s))
        if isPlaying {
            stopAutoAdvance()
            startAutoAdvance()
        }
    }

    func adjustSpeed(delta: Double) {
        setSpeed(speed + delta)
    }

    // MARK: - Internals

    private func resetSceneTime(playing: Bool) {
        accumulatedLocal = 0
        playSessionStart = playing ? Date().timeIntervalSinceReferenceDate : nil
    }

    private func currentLocalTimeNow() -> Double {
        guard let start = playSessionStart else { return accumulatedLocal }
        let live = (Date().timeIntervalSinceReferenceDate - start) * speed
        let dur = sceneDurationFor(address)
        return max(0, min(dur, accumulatedLocal + live))
    }

    /// Schedule a one-shot task that fires when localTime hits the next
    /// scene boundary in the current direction of travel:
    ///
    ///   - speed > 0: fires when localTime reaches sceneDuration (advance)
    ///   - speed < 0: fires when localTime reaches 0          (retreat)
    ///   - speed == 0: never fires (frozen)
    ///
    /// Crossing a boundary jumps to the neighboring scene and re-anchors
    /// localTime at the appropriate end.
    private func startAutoAdvance() {
        advanceGeneration += 1
        let myGen = advanceGeneration
        let dur = sceneDurationFor(address)
        let now = currentLocalTimeNow()

        let interval: Double
        if speed > 0.001 {
            interval = max(0.05, (dur - now) / speed)
        } else if speed < -0.001 {
            interval = max(0.05, now / -speed)
        } else {
            return  // 0 speed → frozen, no advance
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, self.advanceGeneration == myGen, self.isPlaying else { return }
            if self.speed > 0.001 {
                if self.currentGlobal < self.totalScenes - 1 {
                    self.currentGlobal += 1
                    self.resetSceneTime(playing: true)
                    self.startAutoAdvance()
                } else {
                    self.isPlaying = false
                    self.playSessionStart = nil
                }
            } else if self.speed < -0.001 {
                if self.currentGlobal > 0 {
                    self.currentGlobal -= 1
                    let prevDur = self.sceneDurationFor(self.address)
                    self.accumulatedLocal = prevDur
                    self.playSessionStart = Date().timeIntervalSinceReferenceDate
                    self.startAutoAdvance()
                } else {
                    self.isPlaying = false
                    self.playSessionStart = nil
                }
            }
        }
    }

    private func stopAutoAdvance() {
        advanceGeneration += 1
    }
}
