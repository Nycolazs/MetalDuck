# Troubleshooting

## App opens but no frames are shown

Symptoms:
- Status may show running but output stays static/empty.

Checks:
1. macOS **Screen Recording permission** is granted.
2. Selected source (window/display) is still valid and visible.
3. Click `Refresh` and reselect the source.

## CAP/OUT numbers do not change

Checks:
1. Make sure capture actually started (`Start Scaling`).
2. Use a moving source (video/game) to verify refresh.
3. Toggle `FG OFF` then `FG ON` and compare `OUT`.

## 30 -> 60 does not happen

Checks:
1. Source must be truly ~30 FPS.
2. Set `Capture FPS = 30`.
3. Set `FG ON`, `Mode = 2x`.
4. Set `Target FPS >= 60`.
5. Confirm `CAP ~30` and `OUT ~60` in stats.

## Black screen for some apps/videos

Likely DRM/protected content limitation on macOS capture APIs.

## Build issues with SDK/toolchain mismatch

Use explicit SDKROOT:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build
```

If mismatch persists, align Xcode/CLT versions.
