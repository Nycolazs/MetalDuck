# Frame Generation

## Current implementation

MetalDuck currently supports two FG paths:

1. **MetalFX interpolation path** (preferred)
- Requires device/API support and auxiliary inputs (motion/depth/UI).
- In this project state, this path is prepared but effectively unavailable in the current SDK/runtime setup.

2. **Blend interpolation fallback** (active)
- Uses previous + current upscaled frame and blends them.
- Modes:
  - `2x`: one inserted frame at blend factor `0.5`
  - `3x`: two inserted frames at blend factors `1/3` and `2/3`

## Quality expectations

- Works for smooth motion uplift in many desktop/video scenarios.
- Can produce ghosting/halo artifacts on fast motion or occlusion-heavy scenes.
- This is expected without true optical flow / game-native motion vectors.

## Why game integration matters

High quality FG needs consistent:
- motion vectors,
- depth,
- UI isolation.

Desktop capture alone does not provide that reliably.
