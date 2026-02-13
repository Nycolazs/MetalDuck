# Troubleshooting

## "No frames received"

Checks:
1. Confirm macOS Screen Recording permission is granted for MetalDuck.
2. Click `Refresh` and reselect capture source.
3. If `Window` mode fails for a specific app, try `Display` mode.
4. Keep source window visible (some apps throttle hidden windows).

## Output FPS lower than source FPS

Checks:
1. Reduce output size (or disable fullscreen) and compare again.
2. Try `FG Off` to validate baseline rendering throughput.
3. If using `FG 3x`, test `FG 2x` first.
4. Lower scale factor or disable Dynamic Resolution constraints.

## 30 -> 60 does not happen

Use this exact baseline:
1. Source is truly 30 FPS.
2. `Capture FPS = 30`.
3. `Frame Generation = On`, `Mode = 2x`.
4. `Target FPS = 60`.
5. Confirm output HUD shows `GEN FPS > 0` and `OUT` near 60.

## Colors look washed out

Checks:
1. Ensure source and output are on the same display while testing.
2. Keep capture dynamic range in SDR (default in this project).
3. Verify your display profile is not switching between SDR/HDR modes.

## Capture works but quality looks unchanged

Checks:
1. Increase output window size or go fullscreen on output window.
2. Verify `INPUT -> OUTPUT` in HUD shows larger output dimensions.
3. Compare `Native Linear` vs `MetalFX Spatial` in the same scene.

## DRM / protected content shows black

Some protected surfaces cannot be captured through ScreenCaptureKit.
Use non-protected content to validate the pipeline.
