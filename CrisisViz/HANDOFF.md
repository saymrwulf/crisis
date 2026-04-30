# CrisisViz Handoff Document

## What This Is
A native macOS 26 SwiftUI visualizer for Mirco Richter's Crisis consensus protocol. Full-screen keynote-style presentation with Liquid Glass chrome, Canvas-based 60fps rendering, 36 scenes across 10 chapters.

## Current State: App Runs, Core Animation Bugs Fixed

The app builds and runs: `swift build && swift run CrisisViz` from `/Users/oho/GitClone/ClaudeCodeProjects/crisis/CrisisViz/`.

### What Was Just Fixed (This Session)

Three root-cause bugs that made the app feel like "slide after slide with hard jumps":

1. **`.id(engine.currentGlobal)` was destroying views on every scene change** (`ImmersiveView.swift:16`). Changed to `.id(engine.address.chapter)` so views only recreate on chapter transitions. Within a chapter, the Canvas stays alive and `sceneIndex` updates smoothly.

2. **ALL time-based animations were broken across 9 of 10 chapters.** Every chapter used `timeline.date.timeIntervalSinceReferenceDate` (~800M seconds) as `time`, so `min(1.0, time * 0.2)` was always 1.0. Nothing ever animated — Ch07 sort, Ch09 erasure coding, Ch03 partition split, Ch10 shield appear — all frozen at final state. Fixed by adding scene-local time tracking (`sceneStartTime` + `lastSceneIndex` pattern) to Ch01, Ch03, Ch04, Ch05, Ch06, Ch07, Ch08, Ch09, Ch10. Ch02 already had it.

3. **Scene duration was 4s but animations need 5-10s.** Changed `sceneDuration` from 4.0 to 8.0 in `SceneEngine.swift`.

### What the User Has NOT Yet Verified

- The user has not yet tested the live app with these fixes. They restarted Claude Code before testing.
- Smooth within-chapter transitions (the main complaint) — needs live verification
- Whether 8s per scene is the right duration
- Whether cross-fade on chapter transitions feels good

## Architecture (Key Files)

```
Sources/CrisisViz/
  App/CrisisApp.swift              — entry point, --testbed flag
  Engine/SceneEngine.swift         — navigation state, auto-advance timer, sceneDuration=8s
  Model/ChapterDefinitions.swift   — SceneAddress, AllChapters (10 chapters, 36 scenes total)
  Model/SimulationData.swift       — crisis_data.json parsing
  Model/ConsensusData.swift        — DataManager, NodeSnapshot, VertexData, EdgeData
  Views/ImmersiveView.swift        — full-screen container, .id(chapter) for cross-fade
  Views/SceneRouter.swift          — switch on chapter → chapter view with sceneIndex
  Glass/GlassNarration.swift       — Liquid Glass narration panel (bottom-left)
  Glass/GlassControls.swift        — Liquid Glass control bar (bottom-center)
  Canvas/DAGLayoutEngine.swift     — DAGLayout: position computation + Canvas drawing helpers
  Chapters/Ch01-Ch10_*.swift       — one file per chapter, Canvas+TimelineView rendering
  Testbed/SceneCapture.swift       — ImageRenderer-based PNG capture of all scenes
```

## Key Design Patterns

### Scene-Local Time (every chapter must have this)
```swift
@State private var sceneStartTime: Double = 0
@State private var lastSceneIndex: Int = -1

// Inside TimelineView { timeline in Canvas { ... } }:
let now = timeline.date.timeIntervalSinceReferenceDate
var localTime = now - sceneStartTime
if lastSceneIndex != sceneIndex { localTime = 0 }

// Plus .onChange(of: sceneIndex) and .onAppear to reset sceneStartTime
```

### Progressive Reveal (Ch02)
Layout is computed from the FULL dataset (step 9, all vertices). Only a subset is revealed per scene via `sceneVertexCount`. Positions never jump because layout input doesn't change.

### Navigation
- Arrow keys ← → navigate scenes linearly across all chapters
- Space = play/pause auto-advance
- Within a chapter: sceneIndex changes, view stays alive, Canvas updates smoothly
- Between chapters: `.id(chapter)` changes, cross-fade via `.transition(.opacity)`

## User's Standing Complaints (from prior messages)

1. "transitions are like slide after slide" — **should be fixed** by the `.id(chapter)` change + scene-local time, but NOT YET VERIFIED by user
2. "content cut off on right side" — fixed earlier via position clamping + asymmetric margins in DAGLayoutEngine
3. "improve the UX harness so you can have the same experience like a human" — testbed is still static PNGs. Fundamental limitation: can't verify animation smoothness from snapshots. The testbed verifies layout/composition, not motion.

## Testbed

`swift run CrisisViz --testbed` captures 36 PNGs to `~/Desktop/CrisisViz_Testbed/`. Useful for layout verification. Cannot test animation quality — that requires running the live app.

## Data

`crisis_data.json` in Resources/ — pre-computed simulation with 9 honest + 1 byzantine node, 10 consensus steps. Each step has vertices, edges, round info, total ordering positions.

## Build

```bash
cd /Users/oho/GitClone/ClaudeCodeProjects/crisis/CrisisViz
swift build    # ~4s on Apple Silicon
swift run CrisisViz           # live app
swift run CrisisViz --testbed # PNG captures
```

Requires macOS 26 (Tahoe), swift-tools-version 6.2, .macOS(.v26).
