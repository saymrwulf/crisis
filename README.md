# crisis

A proof-of-concept and educational artifact for Mirco Richter's [_Crisis_ paper](Crisis.mirco-richter-2019.pdf) — a DAG-based BFT consensus protocol with a data-availability layer.

This repo contains:

- a small **Go PoC** of the protocol (`src/`, `tests/`),
- a **Python recorder** that exports a simulation run to JSON (`pyproject.toml`),
- **CrisisViz** — a native macOS / SwiftUI curriculum visualizer that walks the protocol end to end across ten chapters: cast intro, gossip mechanics, partition, round derivation, virtual voting, leader election, total order, the data-availability problem, erasure-coded recovery, and Byzantine fork detection.

Everything is in extreme slow motion and serialized for didactic clarity. A signed speed slider scrubs the chapter forward and backward at any rate from −16× to +16×; narration in the overlay is bound to whichever beat the playhead is on.

Build:

```sh
cd CrisisViz
swift build              # dev binary
./bundle.sh              # produce CrisisViz.app + open
swift run CrisisViz --testbed   # PNG sweep + invariant + MP4 harness
```

The viewer is the master of time. Pull the slider.
