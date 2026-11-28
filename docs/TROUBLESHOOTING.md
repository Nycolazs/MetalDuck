# Troubleshooting

## "No frames received"

Checks:
1. Confirm macOS Screen Recording permission is granted for MetalDuck.
2. Press `Choose` and pick the source again.
3. If a window will not capture, pick its display instead, or try the `Window` list.
4. Keep the source window visible (some apps stop drawing when hidden).

## The picture freezes with Centred or Fill display placement

Over the source, the overlay leaves a one-point strip of the window uncovered, because
some apps (Firefox, for one) stop drawing once macOS reports their window as fully
hidden. A centred or full-display picture can cover the whole window. If the picture
freezes, move the source window so part of it shows beside the picture, put it on another
display, or go back to `Over source`.

## Clicks do not land where the picture shows them

With Centred or Fill display placement the picture is not where the source window is, and
the picture never takes clicks: they go to whatever is under the pointer. Use `Over
source` for anything you click on. Video, and games that capture the mouse, are not
affected.

## The system picker does not list a window

A window that is full screen on another desktop may be missing. Switch to that desktop
first, or use the `Window` list, which includes full-screen windows.

## Output FPS lower than source FPS

Checks:
1. Try frame generation off, to see what plain presenting manages.
2. If using 3× or 4×, test 2× first.
3. Set Resolution to Manual and lower the input size: frame generation works at that size.
4. Or turn on Dynamic resolution and lower its Minimum.

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
1. Check the resolution in the stats row. If input and output are the same, nothing is
   being scaled: the source is already at the overlay's size.
2. Set Resolution to Manual with an input smaller than the output.
3. Compare `Native Linear` and `MetalFX Spatial` in the same scene.

## DRM / protected content shows black

Some protected surfaces cannot be captured through ScreenCaptureKit.
Use non-protected content to validate the pipeline.
