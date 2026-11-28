# Architecture

## Package layout

- `MetalDuckKit` (`Sources/MetalDuck`): everything. A library, so it can be tested.
- `MetalDuck` (`Sources/MetalDuckApp`): the executable. It calls `MetalDuckApplication.run()`.
- `MetalDuckKitTests` (`Tests/MetalDuckKitTests`): tests for the pure logic.

`Present.metal` is bundled as source and compiled at launch, so building does not need
the Metal Toolchain.

## Pipeline overview

1. The user chooses a source: `ContentPicker` (the system picker) gives a content filter,
   which `PickedContent` turns into a capture target.
2. `ScreenCaptureKitCaptureService` captures `CMSampleBuffer` frames at the size
   `ScalePlan.streamSize` gives, skips repeated pictures and applies the capture rate.
3. Frame image buffers are wrapped as `MTLTexture` using `CVMetalTextureCache`.
4. `RendererCoordinator` stages frames, builds in-between frames, scales the frame to be
   shown to `ScalePlan.renderSize`, and presents it.
5. `ScalingOverlayController` places the overlay as `ScalePlan.overlayPlan` says.

## Main modules

- `App/`
  - `AppDelegate`: startup, windows, Screen Recording permission.
  - `MainViewController`: session orchestration. Owns the one `CaptureConfiguration`.
  - `ControlPanelView`, `ResolutionField`, `GlassUI`: the control panel.
  - `ScalingOverlayController`: the overlay window.
  - `OutputViewController`: the stats overlay.
- `Capture/`
  - `ContentPicker`: wrapper around `SCContentSharingPicker`.
  - `CaptureTarget`: `CaptureTarget`, `PickedContent`, `CaptureConfiguration`.
  - `ScreenCaptureKitCaptureService`: the stream, window following, live reconfiguration.
  - `CaptureSourceCatalog`: the older display and window lists.
- `Rendering/`
  - `RendererCoordinator`: render loop, frame ring, timing, scaling, stats.
  - `ScalePlan`: capture size, render size, present scale, overlay frame. Pure arithmetic.
  - `Shaders/Present.metal`: the present pass and every frame generation kernel.
- `Upscaling/`
  - `MetalFXSpatialUpscaler`: `MTLFXSpatialScaler` wrapper. Used only to scale up.
- `FrameGeneration/`
  - `MetalFXFrameGenerationEngine`, `VisionFlowProvider`, `BlockMotionEstimator`,
    `FlowSplatter`: motion estimation and the in-between frame.
- `Core/`
  - `RenderSettings`, `Profile`, `ProfileManager`: settings and their storage.
  - `PipelineLog`: timings and events for the Monitor.

## Resolution

Two sizes are in play, and both are planned in `ScalePlan`:

- **Input**: what the stream captures. Automatic keeps the source's shape within the pixel
  count of 1920×1080. Manual is the largest size of the source's shape inside the typed
  size. Never more than the source has. Frame generation runs at this size.
- **Output**: what the scaler renders to. Automatic is the overlay's own pixels. Manual is
  the typed size, held to the overlay's pixels. A target within 1% of the input skips the
  scaler.

Over the source, the overlay shows only the part of the source that is on screen, less a
one-point strip. `OverlayPlan.sourceCrop` carries that part to the present pass so the
picture stays lined up with the window.

## Frame generation model

- Captures are copied into a small timestamped ring.
- `VisionFlowProvider` asks Vision for forward and backward optical flow for that exact pair.
- Output runs a little behind capture. `flowInterpolate` warps both frames to the displayed moment and falls back to a blend where the vectors disagree.
- The full description is in the README and in `docs/FRAME_GENERATION.md`.

## Telemetry

`RendererStats` publishes:
- source rate: what the source sends, before repeats are skipped and the cap is applied
- capture rate: frames kept per second
- generated and presented rates
- input and output resolution, and the scale between them

## Design constraints

- Desktop capture does not provide game-grade motion or depth vectors, so quality is
  best effort.
- The overlay never takes mouse events. Away from the source, clicks do not land where
  the picture shows them.
