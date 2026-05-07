import SwiftUI

/// Full-screen immersive container: canvas scene + glass narration + glass controls.
/// Owns the single TimelineView that drives all chapter animations via `engine.localTime(at:)`.
///
/// Also owns `InspectionState` and overlays `VertexInspectorOverlay` whenever a
/// Ch02 vertex has been clicked. The inspector dims out narration/controls and
/// dismisses on tap or ESC.
struct ImmersiveView: View {
    @State private var engine = SceneEngine()
    @State private var dm = DataManager()
    @State private var inspection = InspectionState()
    @State private var narrationExpanded = true

    var body: some View {
        ZStack {
            // Single TimelineView at the top — chapters are pure renderers below.
            // The chapter is wrapped in an HStack with the persistent CastSidebar
            // (left) and LegendSidebar (right). Chapters never know about the
            // sidebars; they just see a slightly narrower canvas. The sidebars
            // are part of the scene rather than overlays so they morph naturally
            // alongside chapter content rather than floating on top of it.
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                let localTime = engine.localTime(at: timeline.date)
                HStack(spacing: 0) {
                    CastSidebar()
                    SceneRouter(
                        address: engine.address,
                        localTime: localTime,
                        engine: engine,
                        dm: dm,
                        inspection: inspection
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(engine.address.chapter)  // recreate only on chapter change
                    // Inter-chapter morph: slower asymmetric cross-fade. Old
                    // chapter exits at 0.55s; new chapter enters at 0.85s. Up
                    // to ~1s of "no new info" is accepted by the redesign in
                    // exchange for visual continuity (no hard cuts between
                    // wildly different topologies).
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.85)),
                        removal:   .opacity.animation(.easeInOut(duration: 0.55))
                    ))
                    LegendSidebar()
                }
                .background(.black)
            }

            // Narration overlay — bottom left (dimmed while inspecting).
            // Wrapped in its OWN TimelineView so the displayed text
            // updates at frame rate as the active beat changes (Ch01 is
            // beat-bound; other chapters fall back to per-scene text).
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let live = engine.localTime(at: timeline.date)
                VStack {
                    Spacer()
                    HStack {
                        GlassNarration(
                            title: sceneTitle,
                            narration: liveNarration(localTime: live),
                            chapterTitle: engine.currentChapter.title,
                            chapterIndex: engine.address.chapter,
                            sceneIndex: engine.address.scene,
                            sceneCount: engine.currentChapter.sceneCount,
                            globalSceneIndex: engine.address.globalIndex,
                            totalScenes: AllChapters.totalScenes,
                            isExpanded: $narrationExpanded
                        )
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 80)
                }
            }
            .opacity(inspection.isActive ? 0 : 1)

            // Controls — bottom center (dimmed while inspecting)
            VStack {
                Spacer()
                GlassControls(engine: engine)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 20)
            }
            .opacity(inspection.isActive ? 0 : 1)

            // Vertex inspection overlay (above everything when active)
            if inspection.isActive {
                VertexInspectorOverlay(
                    state: inspection,
                    dm: dm,
                    onDismiss: dismissInspection
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onKeyPress(.leftArrow) {
            if inspection.isActive { return .ignored }
            navigateWithTransition { engine.previous() }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if inspection.isActive { return .ignored }
            navigateWithTransition { engine.next() }
            return .handled
        }
        .onKeyPress(.space) {
            if inspection.isActive { return .ignored }
            engine.togglePlay()
            return .handled
        }
        .onKeyPress(.escape) {
            if inspection.isActive {
                dismissInspection()
                return .handled
            }
            return .ignored
        }
        .onChange(of: engine.address.chapter) { _, _ in
            // Switching chapters dismisses any active inspection.
            if inspection.isActive { dismissInspection() }
        }
        .task { dm.load() }
    }

    private func dismissInspection() {
        withAnimation(.easeInOut(duration: 0.3)) {
            inspection.clear()
        }
    }

    private func navigateWithTransition(_ action: () -> Void) {
        // 0.6s wraps the chapter-id change so the asymmetric transition above
        // has enough time to cross-fade. Scene changes within a chapter don't
        // trigger view recreation (`.id` unchanged), so this duration only
        // affects chapter boundaries.
        withAnimation(.easeInOut(duration: 0.6)) {
            action()
        }
    }

    private var sceneTitle: String {
        let addr = engine.address
        return SceneNarrations.title(chapter: addr.chapter, scene: addr.scene)
    }

    private var sceneNarration: String {
        let addr = engine.address
        return SceneNarrations.narration(chapter: addr.chapter, scene: addr.scene)
    }

    /// Beat-bound narration for chapters that have a serial timeline
    /// (currently only Ch01); falls back to scene-bound narration for
    /// every other chapter.
    private func liveNarration(localTime: Double) -> String {
        let addr = engine.address
        switch addr.chapter {
        case 0:
            return Ch00Scenes.narrationAt(sceneIndex: addr.scene, localTime: localTime)
        case 1:
            return Ch01Scenes.narrationAt(sceneIndex: addr.scene, localTime: localTime)
        case 2:
            return Ch02Scenes.narrationAt(sceneIndex: addr.scene, localTime: localTime)
        default:
            return SceneNarrations.narration(chapter: addr.chapter, scene: addr.scene)
        }
    }
}
