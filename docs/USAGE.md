# Usage

## Start a session

1. Launch MetalDuck.
2. Grant Screen Recording permission if prompted.
3. Click `Refresh` to load capture targets.
4. Select mode/source and press `Scale`.

## Capture modes

- `Automatic`: picks a valid source automatically.
- `Display`: capture an entire monitor.
- `Window`: capture one specific app window.

## Output behavior

- A separate output window opens and shows processed content.
- The output window is resizable and supports macOS fullscreen.
- The HUD displays live processing metrics.

## HUD metrics

- `SOURCE FPS`: source feed cadence.
- `CAP FPS`: captured frames per second.
- `GEN FPS`: generated frames per second.
- `OUT FPS`: output presentation FPS.
- `INPUT -> OUTPUT`: processed resolution mapping.

## Recommended presets

- `Performance`: lowest latency, minimal processing.
- `Balanced`: default for 30->60 workflow.
- `Quality`: stronger upscale / heavier processing.

## Validation scenarios

### A) Upscaling check

1. Disable FG.
2. Increase `Scale`.
3. Confirm HUD output resolution increases.

### B) 30 -> 60 check

1. Use a real 30 FPS source.
2. Set `Capture FPS = 30`, `FG = On`, `Mode = 2x`, `Target FPS = 60`.
3. Confirm `GEN FPS > 0` and `OUT` around 60.

### C) Baseline check

1. Disable FG.
2. Confirm output remains smooth and close to source cadence.

## Shortcut

- `Space`: start/stop session.
