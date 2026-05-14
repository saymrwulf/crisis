# CrisisViz — Agent-to-Agent Handoff

> **Audience.** This file is the engineering log for the **next coding agent** to pick up this project. It assumes Swift, SwiftUI, macOS 26, and the Crisis protocol context from `../README.md`. For human-facing orientation see `README.md` next to this file.

Last updated: **2026-05-14**.

---

## 1. Current state — what's shipped

- **All 10 chapters migrated** to the serial-beat timeline pattern (pure `state(at: t) -> WorldState`, scrubbable −16× to +16×, beat-bound narration).
- **Testbed green** at the last clean run: 38/38 invariants pass, 0 source-audit errors, 36/36 MP4 clips written, 279 PNGs sane, 12/12 resize cases pass.
- **`origin/master` at `fb9bc9c`** — working tree was clean before this documentation/testing pass. After this pass: README.md/INSTALL.md/LICENSE/CrisisViz README&HANDOFF/package-dmg.sh/Python tests landed.
- **Bundle pipeline works.** `./bundle.sh` produces a working `CrisisViz.app`. `./package-dmg.sh` produces a working `CrisisViz.dmg` (ad-hoc signed; first-open Gatekeeper warning, right-click → Open).

If you can't run the testbed and confirm it's green, **stop and fix that first** before making curriculum changes.

---

## 2. The pure-function timeline pattern (this is the architecture)

Every chapter is split into two files:

```
Sources/CrisisViz/Engine/ChXXTimeline.swift     pure model (state machine over t)
Sources/CrisisViz/Chapters/ChXX_Foo.swift       thin Canvas renderer (no logic)
```

The timeline file is the contract. It contains:

1. **A typed `BeatKind` enum** capturing the chapter's micro-events (e.g. `introduce(name:)`, `compose(by:)`, `sealAccepted(at:)`, `gossipFly(from:to:)`, `linkBroken`, …).
2. **A `WorldState` struct** holding the cumulative state at a moment in time (introduced cast set, accepted vertices per lane, in-flight envelopes, broken links, vault contents, …).
3. **A flat `[Beat]` list.** Each `Beat` has `(id, kind, durationSeconds, narration)`. Narration is one sentence describing what that beat _physically shows_.
4. **A `state(at: Double) -> WorldState` pure function.** Replays every beat up to `t` produces the state. Pure ⇒ scrubbable + reverse-playable. **No monotonic accumulators, no hidden `@State`.**
5. **A `ChXXScenes` enum** with `sceneStarts`, `sceneDurations`, `timelineT(sceneIndex, localTime)`, `narrationAt(sceneIndex, localTime)`. The chapter's existing scene count stays — scenes become navigation labels on the unified timeline.

The renderer file is thin:

```swift
TimelineView(.animation) { timeline in
    Canvas { ctx, size in
        let t = ChXXScenes.timelineT(sceneIndex: sceneIndex, localTime: localTime)
        let world = ChXXTimeline.state(at: t)
        // draw the world from `world`. No per-scene switch.
    }
}
```

`SceneEngine.durationOverrides` gets per-scene durations matching the timeline's windows. `ImmersiveView.liveNarration` adds a case for the new chapter, reading from `ChXXScenes.narrationAt`.

---

## 3. Pedagogy invariants the renderer MUST hold

These are not stylistic preferences — the testbed enforces them. Break one, the source audit fails.

- **Strictly serial.** Never two simultaneous events on screen. Every beat owns its time window exclusively.
- **Cast appears via `introduce(...)` beats only.** Lanes for not-yet-introduced cast are invisible. Their lane labels are also hidden.
- **Lane = lifeline.** A vertex belonging to player $P$ sits exactly on $P$'s lane Y. No jitter, ever. Source audit forbids reintroducing `hashJitterY`.
- **Composing and open-envelope share ONE fixed top-center slot** (`detailSlotRect`, y ≈ 16..146 + ~30pt caption). They never co-occur on the timeline.
- **In-flight envelopes draw on a courier track 36pt above the lane axis** so they don't collide with the just-sealed accepted vertex on the sender's lane.
- **Cast colors via `dm.castColor(for:)`** — never `palette[i]`. Lane order via `dm.castOrderedNodes()` — never raw `sim.nodes` (would put Dave at lane 8 below 5 peers).
- **Beat tag** (small, faint, top-right) so PNG sweeps can be matched to a specific beat for debugging.
- **Scene indicator** `CH X.Y (n/N)` badge on the narration panel, visible even when collapsed.

When designing a new beat, picture all of these on screen at once (lane labels left margin, cast circles with ~50pt halos, `detailSlotRect` top band, courier track at lane Y − 36, accepted-vertex rows right of cast circles, `GlassNarration` bottom-left ~340pt × 250pt expanded, `GlassControls` bottom ~80pt). If the new beat lands on top of any of those, redesign before shipping.

---

## 4. Hard-won rules from past sessions

These are the ones that bite repeatedly. Memorize them.

| Rule | Why |
|---|---|
| Restart the live `.app` after Swift changes | The Dock icon launches `CrisisViz.app`, not the `swift-run` dev binary. Run `./bundle.sh --no-launch && open CrisisViz.app`. |
| Testbed can't verify animation smoothness | Static PNG sweeps catch layout bugs; MP4 clips catch motion bugs; but the user-experience of scrub feel can only be evaluated live. Always restart and watch. |
| Narration ≡ canvas | When a scene's title is a narrative beat ("Aaron speaks. Ben listens."), hand-curate the visible-vertex set to match. Progressive reveal by `sceneVertexCount` alone will under-show or over-show and make the narration lie. |
| Arrows must be visible | Edges drawn as `Path` lines without arrowheads are not arrows. Use `drawArrowEdge`. Every narrated causal claim ("Ben copies Aaron") must be physically renderable from the data. |
| Layout is computed from the full dataset | Compute positions from `sim.nodes[step=lastStep]`, reveal only a subset via `sceneVertexCount`. Positions never jump because layout input doesn't change. |

---

## 5. Test harness reference

`swift run CrisisViz --testbed` → `~/Desktop/CrisisViz_Testbed/`. Five layers:

| Layer | File | Catches |
|---|---|---|
| Narrative invariants | `Testbed/NarrativeInvariants.swift` | logical claims about staging, cast assignment, geometry, sim convergence |
| Source pattern audit | `Testbed/SourceAudit.swift` | regex-forbidden patterns (lane jitter, `palette[i]`, hardcoded PIDs) |
| Per-scene MP4 clips | `Testbed/SceneVideoCapture.swift` | animation continuity (36 clips at 8s/30fps) |
| PNG time-scrubbing sweep | `Testbed/SceneCapture.swift` | frozen interpolators, all-black renders, label drift |
| Window resize + sanity | `Testbed/SceneCapture.swift` | clamping correctness, tiny renders, byte-identical frames |

When adding a new chapter / scene / design rule, **update the corresponding layer in the same commit**:

- New chapter → add invariants in `NarrativeInvariants.swift` (expected visible vertex count, expected cast members, expected edges).
- New design rule → add a `Rule` to `SourceAudit.rules` with the legitimate definition site whitelisted in `allowedFiles`.
- New animation → confirm the scene's MP4 actually contains motion. Scrub it.

---

## 6. Known open items

Surfaced from working memory at handoff. None blocking, all valuable:

1. **DA-chapter polish (Ch07 / Ch08).** Both are on the serial-timeline pattern but the shard / vault animations are still abstract relative to the cast-on-lane discipline elsewhere. Could be tightened so shards are physically carried by Aaron / Ben / Carl / Dave lanes.
2. **Per-scene visible-vertex-count invariants.** Currently 38 logical invariants; adding count assertions per scene would catch staging regressions before they ship.
3. **`LaneRenderKit` extraction.** Geometry helpers `castLaneY`, `castPosition`, `castColor`, `drawIntroducedLanes`, `drawCastFigures` are duplicated across cast-heavy chapters (Ch00, Ch01, Ch02, Ch09 — four adopters now, more than enough). Factor into a shared file.
4. **Animation smoothness verification protocol.** No testbed signal — only live-app eyeballing on Ch01 staging, Ch02 partition, Ch06 total-order convergence, Ch09 byzantine. Recurring blind spot; consider an MP4 difference-frame analyzer.
5. **CrisisNode / gossip TCP integration tests.** The real distributed runtime (`src/crisis/node.py`, `src/crisis/gossip.py`) has zero tests. Not blocking the visualizer (which uses `SimulatedNode`), but the deployable side is currently unverified.

---

## 7. How to resume

```sh
cd /Users/oho/GitClone/ClaudeCodeProjects/crisis/CrisisViz

# 1. Compile + trust SourceKit
swift build

# 2. After source changes: rebuild the bundle
./bundle.sh --no-launch
open CrisisViz.app

# 3. Verify the testbed before committing curriculum changes
swift run CrisisViz --testbed
# read ~/Desktop/CrisisViz_Testbed/INVARIANTS.md, SOURCE_AUDIT.md,
# VIDEO_CLIPS.md, MANIFEST.md, SANITY.md — all must be green

# 4. For distribution
./package-dmg.sh
# produces CrisisViz.dmg, prints SHA-256
```

If something feels broken, check in this order: (1) is `crisis_data.json` present and non-empty? (2) does `swift build` succeed cleanly? (3) does the dev binary `swift run CrisisViz` produce a window? (4) does `./bundle.sh` succeed and `open CrisisViz.app` show the same window with a Dock icon? (5) does the testbed run to completion?
