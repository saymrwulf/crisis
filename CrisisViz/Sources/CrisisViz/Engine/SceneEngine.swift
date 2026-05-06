import SwiftUI

/// Observable engine driving the immersive linear scene flow.
/// Single source of truth for scene-local time. Chapters consume `localTime(at:)`.
@MainActor
@Observable
final class SceneEngine {
    private(set) var currentGlobal: Int = 0
    private(set) var isPlaying: Bool = false

    /// Wall-clock reference (Date.timeIntervalSinceReferenceDate) when the current scene started.
    private(set) var sceneStartReference: Double = 0

    var speed: Double = 1.0
    let totalScenes: Int

    /// Monotonic counter; incremented on every stopAutoAdvance() to invalidate in-flight asyncAfter blocks.
    private var advanceGeneration: Int = 0
    let sceneDuration: Double = 8.0  // default at 1x

    /// Per-(chapter,scene) duration overrides. Some scenes — notably the
    /// Ch01 scene-3 slow-motion gossip dramatization — can't compress into
    /// 8 seconds without losing the pedagogy. List them explicitly here.
    private static let durationOverrides: [SceneAddress: Double] = [
        SceneAddress(chapter: 1, scene: 3): 24.0   // gossip dramatization
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

    /// Compute scene-local time at a given wall-clock date, scaled by speed.
    /// Returns 0 if the scene hasn't actually started yet (e.g. fresh launch).
    func localTime(at date: Date) -> Double {
        guard sceneStartReference > 0 else { return 0 }
        let delta = date.timeIntervalSinceReferenceDate - sceneStartReference
        return max(0, delta * speed)
    }

    /// Progress within current scene (0..1), capped at 1. Honors per-scene
    /// duration overrides so a long scene's progress bar doesn't max out
    /// after only 8 seconds.
    func progress(at date: Date) -> Double {
        min(1.0, localTime(at: date) / sceneDurationFor(address))
    }

    init() {
        self.totalScenes = AllChapters.totalScenes
        self.sceneStartReference = Date().timeIntervalSinceReferenceDate
    }

    // MARK: - Navigation

    func next() {
        let wasPlaying = isPlaying
        stopAutoAdvance()
        if currentGlobal < totalScenes - 1 {
            currentGlobal += 1
            resetSceneTime()
            if wasPlaying { startAutoAdvance() }
        }
    }

    func previous() {
        let wasPlaying = isPlaying
        stopAutoAdvance()
        if currentGlobal > 0 {
            currentGlobal -= 1
            resetSceneTime()
            if wasPlaying { startAutoAdvance() }
        }
    }

    func goTo(global: Int) {
        let wasPlaying = isPlaying
        stopAutoAdvance()
        currentGlobal = max(0, min(global, totalScenes - 1))
        resetSceneTime()
        if wasPlaying { startAutoAdvance() }
    }

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            resetSceneTime()
            startAutoAdvance()
        } else {
            stopAutoAdvance()
        }
    }

    func adjustSpeed(delta: Double) {
        speed = max(0.25, min(4.0, speed + delta))
        if isPlaying {
            stopAutoAdvance()
            startAutoAdvance()
        }
    }

    // MARK: - Internals

    private func resetSceneTime() {
        sceneStartReference = Date().timeIntervalSinceReferenceDate
    }

    private func startAutoAdvance() {
        advanceGeneration += 1
        let myGen = advanceGeneration
        // Auto-advance honors the current scene's effective duration (longer
        // scenes get more time). Speed scaling still applies.
        let interval = sceneDurationFor(address) / max(0.1, speed)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, self.advanceGeneration == myGen, self.isPlaying else { return }
            if self.currentGlobal < self.totalScenes - 1 {
                self.currentGlobal += 1
                self.resetSceneTime()
                self.startAutoAdvance()
            } else {
                self.isPlaying = false
            }
        }
    }

    private func stopAutoAdvance() {
        // Invalidate any pending asyncAfter blocks.
        advanceGeneration += 1
    }
}
