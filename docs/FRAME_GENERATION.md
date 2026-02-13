# Frame Generation

## Current implementation

MetalDuck uses a GPU optical-flow interpolation pipeline:

1. Estimate block motion (`previous` -> `current`) with a compute shader.
2. Build a low-resolution flow texture.
3. Warp both frames toward interpolation time (`t`) in a render pass.
4. Blend warped frames, with fallback stabilization for mismatch-heavy regions.

Modes:
- `2x`: inserts one generated frame between source frames.
- `3x`: inserts two generated frames between source frames.

## Why quality differs from game-integrated FG

Desktop capture does not provide reliable per-pixel game motion vectors, depth, and UI layers.
Because of that, hard occlusions and very fast motion can still show artifacts.

## Practical guidance

For best visual results:
- Keep source visible (avoid browser/background throttling).
- Use `Capture FPS = 30` + `FG 2x` + `Target FPS = 60` for 30->60.
- Use `FG 3x` only when the source cadence is stable and GPU headroom is available.
