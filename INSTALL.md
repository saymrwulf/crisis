# INSTALL — Crisis, CrisisViz, and crisis_agents

End-to-end setup on a fresh macOS box: from blank checkout to running protocol tests, the agent-coordination demo, and the SwiftUI visualizer. Follow top-to-bottom.

---

## 1. Prerequisites

| Tool | Minimum | How to install |
|---|---|---|
| **macOS** | 26 Tahoe | The Swift visualizer targets `.macOS(.v26)`. The Python side runs on any macOS with Python ≥3.11. |
| **Xcode** | 17 | `xcode-select --install` for command-line tools only, or the full Xcode app from the App Store. Provides Swift 6.2 + the macOS 26 SDK. |
| **Python** | 3.11 | Pre-installed on recent macOS; otherwise `brew install python@3.11`. |
| **git** | any | `xcode-select --install` installs it. |
| **Homebrew** | optional | Only needed if you don't already have Python 3.11. Install per [brew.sh](https://brew.sh). |

Verify:

```sh
sw_vers                   # ProductVersion: 26.x
xcodebuild -version       # Xcode 17.x
swift --version           # swift-driver version: 1.x  (Apple Swift version 6.2)
python3.11 --version      # Python 3.11.x
```

---

## 2. Clone and verify

```sh
git clone https://github.com/saymrwulf/crisis.git
cd crisis
ls Crisis.mirco-richter-2019.pdf    # the spec — must exist
```

---

## 3. Python side — protocol PoC

Create a virtualenv and install the package in editable mode with dev extras:

```sh
python3.11 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e ".[dev]"
```

Run the unit tests to verify the algorithm implementations:

```sh
pytest -q
```

Expected: ~170 tests, all green in under a second. If any fail, stop and investigate before continuing — both the visualizer's data pipeline and the agent-coordination layer depend on these.

Try a deterministic in-process simulation:

```sh
python -m crisis.demo --nodes 3 --byzantine 0 --rounds 5
```

You should see consensus rounds advance and a total order emerge.

---

## 4. Run the AI-agent coordination demo

The `crisis-agents` CLI walks a six-phase scenario end-to-end: a closed honest team, a byzantine joiner who equivocates on a fact-check statement, an asynchronous gossip + detection event loop, quorum-ratified alarm, and a multi-signer proof JSON.

### 4a. Mocked agents (deterministic, no API costs)

```sh
crisis-agents demo --out-dir /tmp/crisis_demo
```

Output ends with `proof_<accused>_<statement>.json` in `--out-dir`. To self-verify a proof:

```sh
crisis-agents verify /tmp/crisis_demo/proof_*.json
```

### 4b. Real Claude sub-agents (`--live`)

Install the optional Anthropic SDK extras:

```sh
pip install -e ".[live]"
export ANTHROPIC_API_KEY=sk-ant-...
crisis-agents demo --live --model claude-haiku-4-5-20251001
```

This swaps the three scripted honest agents for `LiveClaudeAgent` instances backed by real Anthropic Messages API calls. The byzantine stays scripted so the equivocation is reliably reproducible. Costs API credits; output is non-deterministic.

Architecture reference: **[src/crisis_agents/README.md](src/crisis_agents/README.md)**.

---

## 5. Regenerate `crisis_data.json` (optional)

The repo ships with a pre-recorded `crisis_data.json` at the root and a bundled copy in `CrisisViz/Sources/CrisisViz/`. Regenerate when you change the protocol code or want a different simulation:

```sh
python -m crisis.export_json --steps 80 -o crisis_data.json
cp crisis_data.json CrisisViz/Sources/CrisisViz/crisis_data.json
```

The defaults (6 honest + 1 byzantine, 80 steps) produce full convergence from step 40 onward — the visualizer's chapters on total order and Byzantine detection depend on having a converged tail.

---

## 6. Swift side — the visualizer

### 6a. Quick dev loop

```sh
cd CrisisViz
swift build              # ~4s on Apple Silicon
swift run CrisisViz      # launches the dev binary
```

Note: the dev binary does not have a Dock icon and lives in `.build/`. For a real `.app` use `bundle.sh`.

### 6b. Build the `.app` bundle

```sh
./bundle.sh              # build + assemble CrisisViz.app + open
./bundle.sh --no-launch  # build only
```

`CrisisViz.app` is created in the current directory. Open it from Finder or the Dock to get the full activation-policy behavior.

### 6c. Build a DMG installer

```sh
./package-dmg.sh         # produces CrisisViz.dmg in the current directory
```

The DMG is ad-hoc signed — on first open macOS Gatekeeper will refuse to launch the app directly. Right-click `CrisisViz` in `/Applications` → **Open** → **Open** in the confirmation dialog. macOS remembers your approval; subsequent launches behave normally.

Distribution flow for a new machine:
1. Copy `CrisisViz.dmg` to the target Mac.
2. Double-click to mount.
3. Drag `CrisisViz` onto the `Applications` symlink.
4. Eject the DMG; launch from `/Applications` (right-click → Open the first time).

### 6d. Run the QA testbed

```sh
swift run CrisisViz --testbed
```

Writes to `~/Desktop/CrisisViz_Testbed/`:

- `INVARIANTS.md` — 38 logical curriculum assertions
- `SOURCE_AUDIT.md` — forbidden-pattern scan (lane jitter, hardcoded palette, etc.)
- `VIDEO_CLIPS.md` — 36 MP4 clips at 8s / 30fps
- `MANIFEST.md` — PNG sweep across all scenes / time offsets
- `SANITY.md` — file-size and freeze-frame checks

All five should be green before shipping changes.

---

## 7. Troubleshooting

**`swift build` fails with “unsupported deployment target”.** Your Xcode does not provide the macOS 26 SDK. Update Xcode to ≥17, or downgrade `Package.swift` to your installed SDK (not recommended — visual features depend on macOS 26 Liquid Glass APIs).

**`swift run CrisisViz` shows a blank window.** The bundled `crisis_data.json` is missing or empty. Run `cp crisis_data.json CrisisViz/Sources/CrisisViz/crisis_data.json` and rebuild.

**Gatekeeper refuses to open the app from the DMG.** Right-click → **Open** the first time. Or remove the quarantine attribute manually: `xattr -dr com.apple.quarantine /Applications/CrisisViz.app`.

**`pytest` fails on `ModuleNotFoundError: crisis`.** Activate the venv (`source .venv/bin/activate`) and reinstall with `pip install -e ".[dev]"`. The `-e` (editable) flag is what makes `import crisis` resolve to `src/crisis/`.

**The visualizer freezes mid-chapter / animations are stuck.** You're running the unbundled `swift-run` binary while the Dock icon launches `CrisisViz.app`. Rebuild the bundle: `./bundle.sh --no-launch && open CrisisViz.app`.

**`crisis-agents --live` fails with `live mode requires the anthropic SDK`.** Install the optional extras: `pip install -e ".[live]"`. The mocked path doesn't need this dependency.

**`crisis-agents --live` fails with `ANTHROPIC_API_KEY`.** Export the key before running: `export ANTHROPIC_API_KEY=sk-ant-...`. The SDK reads it from the environment.
