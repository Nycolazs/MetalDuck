# Architecture

## Overview

Main pipeline:
1. `ScreenCaptureKitCaptureService` receives `CMSampleBuffer` frames.
2. `CVPixelBuffer` is wrapped into `MTLTexture` (`CVMetalTextureCache`).
3. `RendererCoordinator` processes each frame:
   - dynamic resolution scaling,
   - upscaling (MetalFX Spatial or native),
   - frame generation resolve (MetalFX path or blend fallback),
   - final presentation to `MTKView`.
4. `ControlPanelView` updates runtime settings via `SettingsStore`.

## Modules

- `App/`
  - `AppDelegate`: app bootstrap, window, screen capture permission, app icon.
  - `MainViewController`: integrates UI + renderer + capture target selection.
  - `ControlPanelView`: user controls and telemetry display.
- `Capture/`
  - `ScreenCaptureKitCaptureService`: primary capture backend.
  - `CaptureSourceCatalog`: enumerates displays/windows.
  - `FrameCaptureFactory`: backend selection.
- `Rendering/`
  - `RendererCoordinator`: render loop, pacing, stats, frame history, composition.
  - `Shaders/Present.metal`: full-screen pass (sampling, sharpen, blend).
- `Upscaling/`
  - `MetalFXSpatialUpscaler`: `MTLFXSpatialScaler` wrapper.
- `FrameGeneration/`
  - `MetalFXFrameGenerationEngine`: MetalFX interpolation path (stub on current SDK setup).

## Runtime state

- `CaptureConfiguration` controls capture parameters (fps, queue depth, cursor, target size).
- `RenderSettings` controls upscaling/DRS/FG parameters.
- `SettingsStore` provides thread-safe snapshots.
- `RendererStats` publishes CAP/OUT FPS and resolution telemetry to UI.

## Frame generation behavior

- `frameGenerationEnabled = false`
  - Presentation is paced close to capture FPS.
- `frameGenerationEnabled = true`
  - Tries MetalFX interpolation if support + auxiliary textures exist.
  - Fallback uses blend interpolation between previous/current frames:
    - `x2`: one intermediate frame (blend 0.5)
    - `x3`: two intermediate frames (blend 1/3 and 2/3)
