# MetalDuck

MetalDuck is an experimental macOS real-time scaler inspired by Lossless Scaling, built with ScreenCaptureKit + Metal + MetalFX.

It captures a window or display, applies GPU processing (upscaling and optional frame generation), and presents the processed result in a dedicated output window.

## What this project does

- Real-time capture with `ScreenCaptureKit`.
- Metal render pipeline for low-latency presentation.
- MetalFX spatial upscaling (`MTLFXSpatialScaler`).
- Optional frame generation (`2x` / `3x`) with GPU optical-flow estimation + warping.
- Runtime controls for capture FPS, target FPS, scaling, sharpness, dynamic resolution, and FG.
- Live output HUD with `SOURCE / CAP / GEN / OUT FPS`.

## Current limitations (important)

- This is **not** a native game renderer injection path.
- Quality can still differ from Lossless Scaling, especially in fast occlusion scenes.
- Highest FG quality still requires true game motion vectors/depth from engine integration.
- DRM-protected content may not be capturable by macOS APIs.

## Requirements

- Apple Silicon Mac
- macOS 15+
- Swift 6.2 toolchain (or compatible)
- Xcode Command Line Tools

## Build

### Debug

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build
```

### Release

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build -c release
```

## Run

### Debug

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift run
```

### Release binary

```bash
./.build/release/MetalDuck
```

## Create a distributable release zip

```bash
bash scripts/create_release.sh
```

Output:
- `dist/MetalDuck-macos-arm64.zip`

## Quick start (30 -> 60 FPS browser test)

1. Open a true 30 FPS video in your browser.
2. In MetalDuck:
   - Capture mode: `Window`
   - Source: browser window
   - Capture FPS: `30`
   - Frame Generation: `On`
   - FG mode: `2x`
   - Target FPS: `60`
3. Click `Scale`.
4. Keep source window visible (browser may throttle hidden tabs/windows).
5. Confirm in output HUD:
   - `SOURCE` around 30
   - `CAP` around 30
   - `GEN` > 0
   - `OUT` around 60

## Controls that most affect results

- `Capture FPS`: input cadence.
- `Target FPS`: output cadence cap.
- `Frame Generation`: inserts generated frames.
- `Scale` + `Match Output`: controls final processed resolution.
- `Dynamic Resolution`: trades detail for frame stability.

## Repository layout

- `Sources/MetalDuck/App` app lifecycle, control UI, output window.
- `Sources/MetalDuck/Capture` ScreenCaptureKit integration.
- `Sources/MetalDuck/Rendering` main render loop and presentation.
- `Sources/MetalDuck/Upscaling` MetalFX spatial upscaler wrapper.
- `Sources/MetalDuck/FrameGeneration` optical-flow FG engine.
- `docs/` architecture, usage, troubleshooting.

## Documentation

- `docs/ARCHITECTURE.md`
- `docs/USAGE.md`
- `docs/FRAME_GENERATION.md`
- `docs/TROUBLESHOOTING.md`
- `docs/ROADMAP.md`
- `docs/RELEASE.md`

## License

MIT (`LICENSE`).
