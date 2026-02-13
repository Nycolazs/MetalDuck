# MetalDuck v0.1.0

## Highlights

- Reworked render pipeline for stable capture -> process -> present flow.
- New dedicated output window with live HUD telemetry.
- MetalFX spatial upscaling integration refined.
- New optical-flow-based frame generation path (GPU compute + warp interpolation).
- Improved FPS reporting (`SOURCE`, `CAP`, `GEN`, `OUT`).
- Updated all documentation to English.

## What to expect

- Better visual interpolation than simple frame blending.
- Better visibility of whether FG/upscale is actually active.
- Better troubleshooting guidance for browser/window throttling cases.

## Known limitations

- Not equivalent to game-engine-native motion/depth FG.
- Very fast occlusion scenes can still produce artifacts.
- DRM/protected video surfaces may not be capturable.

## Run

```bash
./MetalDuck
```

If running from release package, keep `MetalDuck` and `MetalDuck_MetalDuck.bundle` in the same folder.

## Recommended validation

1. Use a real 30 FPS source.
2. Set `Capture FPS = 30`, `FG = On`, `Mode = 2x`, `Target FPS = 60`.
3. Confirm HUD shows `GEN FPS > 0` and `OUT` near 60.
4. Increase output window size/fullscreen and verify `INPUT -> OUTPUT` indicates real upscale.
