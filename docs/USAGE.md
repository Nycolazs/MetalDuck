# Usage

## Start

1. Launch the app.
2. Grant **Screen Recording** permission when requested.
3. Click `Refresh` to reload capture sources.

## Capture modes

- `Automatic`: prefers visible windows.
- `Display`: captures a whole display.
- `Window`: captures a specific window.

## Core controls

- `Capture FPS`: input capture rate.
- `Queue Depth`: stream buffering depth.
- `Algorithm`: `MetalFX Spatial` or `Native Linear`.
- `Scale`: output scaling factor.
- `Sharpness`: post-upscale sharpening.
- `Dynamic Resolution`: auto-adjusts scale to maintain target FPS.
- `Frame Generation`: inserts intermediate frames.

## Recommended validation tests

### Test A: Upscaling path

1. Keep `FG OFF`.
2. Change `Scale` from `1.0x` to `2.0x`.
3. Verify output resolution changes in telemetry.

### Test B: 30 -> 60 validation

1. Use a known 30 FPS source.
2. Set `Capture FPS = 30`.
3. Set `FG ON`, `Mode = 2x`, `Target FPS >= 60`.
4. Expected: `CAP ~30`, `OUT ~60`.

### Test C: Baseline comparison

1. Set `Capture FPS = 30`.
2. Set `FG OFF`.
3. Expected: `OUT` close to `CAP`.

## Shortcut

- `Space`: toggle start/stop session.
