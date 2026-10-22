# Architecture

## Pipeline overview

1. `ScreenCaptureKitCaptureService` captures `CMSampleBuffer` frames.
2. Frame image buffers are wrapped as `MTLTexture` using `CVMetalTextureCache`.
3. `RendererCoordinator` performs:
   - scale calculation (manual + optional dynamic resolution),
   - upscaling (`MetalFX Spatial` or native resample),
   - optional frame generation,
   - final presentation to output `MTKView`.
4. `OutputViewController` shows real-time telemetry in the output window.

## Main modules

- `App/`
  - `AppDelegate`: startup, windows, permissions bootstrap.
  - `MainViewController`: control panel + session orchestration.
  - `ControlPanelView`: Lossless-inspired runtime controls.
  - `ScalingOverlayController`: dedicated output window lifecycle.
  - `OutputViewController`: output HUD and diagnostics.
- `Capture/`
  - `ScreenCaptureKitCaptureService`: primary capture backend.
  - `CaptureSourceCatalog`: display/window source listing.
  - `FrameCaptureFactory`: backend creation.
- `Rendering/`
  - `RendererCoordinator`: render loop, frame staging, pacing, stats.
  - `Shaders/Present.metal`: final present pass and sharpening.
- `Upscaling/`
  - `MetalFXSpatialUpscaler`: `MTLFXSpatialScaler` wrapper.
- `FrameGeneration/`
  - `MetalFXFrameGenerationEngine`: optical-flow estimate + warp interpolation.

## Frame generation model

- Captures are copied into a small timestamped ring.
- `VisionFlowProvider` asks Vision for forward and backward optical flow for that exact pair.
- Output runs a little behind capture. `flowInterpolate` warps both frames to the displayed moment and falls back to a blend where the vectors disagree.
- The full description is in the README and in `docs/FRAME_GENERATION.md`.

## Telemetry

`RendererStats` publishes:
- `SOURCE FPS` (capture throughput)
- `CAP FPS` (captured frames/sec)
- `GEN FPS` (generated frames/sec)
- `OUT FPS` (presented frames/sec)
- input/output resolution and effective scale

## Design constraints

- Desktop capture does not provide perfect game-grade motion/depth vectors.
- Therefore, quality is best-effort for window/display capture workloads.
