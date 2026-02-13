# MetalDuck

MetalDuck is a macOS prototype for **Lossless Scaling-style capture + upscaling + frame generation** on Apple Silicon using Metal/MetalFX.

## Current status

This is a working local prototype, not a finished product.

What it already does:
- Real-time **window/display capture** with `ScreenCaptureKit`.
- `CVPixelBuffer` -> `MTLTexture` conversion via `CVMetalTextureCache`.
- Upscaling with `MTLFXSpatialScaler` (MetalFX Spatial).
- Presentation pipeline with `MTKView` + sharpen pass.
- Dynamic Resolution Scaling (DRS) with target FPS.
- Frame generation path:
  - tries MetalFX interpolation when auxiliary data is available,
  - currently falls back to blend interpolation (`x2`/`x3`) when motion/depth is not available.
- Lossless Scaling-inspired control panel UI with CAP/OUT FPS telemetry.
- Custom steampunk duck app icon (PNG + ICNS bundled).

## Important limitations

- It does not inject into the original app/game renderer. Output is shown inside MetalDuck's viewport.
- Frame generation without true motion/depth data can produce ghosting on fast motion.
- DRM-protected content may not be capturable on macOS.

## Requirements

- Apple Silicon
- macOS 15+
- Compatible Xcode/CommandLineTools SDK

## Build and run

### 1. Build

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build
```

### 2. Run

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift run
```

## Quick 30 -> 60 FPS test

1. Open a real 30 FPS video in a browser.
2. In MetalDuck:
   - `Mode = Window`
   - select the browser window
   - `Capture FPS = 30`
   - `Frame Generation = ON`
   - `Mode = 2x`
   - `Target FPS >= 60`
3. Click `Start Scaling`.
4. Validate in stats:
   - `CAP` ~30
   - `OUT` ~60

## Project structure

- `Sources/MetalDuck/App` UI, app window, runtime controls.
- `Sources/MetalDuck/Capture` ScreenCaptureKit capture and source catalog.
- `Sources/MetalDuck/Rendering` render loop, pacing, upscaling, FG, presentation.
- `Sources/MetalDuck/Upscaling` MetalFX Spatial wrapper.
- `Sources/MetalDuck/FrameGeneration` MetalFX FG engine/stub.
- `Sources/MetalDuck/Assets` app icon assets.
- `docs/` detailed documentation.

## Detailed docs

- `docs/ARCHITECTURE.md`
- `docs/USAGE.md`
- `docs/FRAME_GENERATION.md`
- `docs/TROUBLESHOOTING.md`
- `docs/ICON_PIPELINE.md`
- `docs/ROADMAP.md`

## License

MIT. See `LICENSE`.
