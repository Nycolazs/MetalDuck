# Frame generation

MetalDuck builds the frames between two real captures. It does not receive motion vectors from a game, so it measures motion itself and shows the result a fraction of a second after the source.

## Capture

ScreenCaptureKit delivers a frame whenever the content changes, at up to the display rate. Each frame keeps the timestamp of that change.

The capture rate in a profile is applied afterwards, by timestamp. Frames closer together than about three quarters of the configured interval are dropped. A 24 fps video under a 30 fps cap therefore stays at an even 41.7 ms, instead of being snapped onto a 33 ms grid.

## Motion

Each accepted frame is copied into a ring of five textures and downscaled on the GPU to at most 800 pixels on the long side. The downscaled image lives in an IOSurface, so Vision reads it without a copy back to the CPU.

`VNGenerateOpticalFlowRequest` revision 1 then estimates the motion. Revision 1 reports vectors in pixels and takes about 20 ms for the forward and backward fields together on an M1 Pro. Revision 2 is more accurate on a few fast objects, but it takes around 150 ms and reports a fraction of a pixel, so a live pipeline cannot use it.

Up to two pairs are computed at once. A result is stored against the two capture ids it came from. If the exact pair is not ready, a result from at most two captures away may be used, and only where the two warped colours still agree.

## The in-between frame

Output trails the newest capture by about one capture interval plus the time the flow took. That delay changes slowly, so it does not show up as a change in speed. The displayed moment is also snapped to the display's refresh, using the time the previous drawable actually reached the screen.

For a moment `t` between captures A and B:

1. The forward field moves A toward B by `t`. The backward field moves B toward A by `1 - t`.
2. Each vector is trusted only if following it and then the opposite field comes back near the start. At the edge of a moving object, the side that can still see the pixel wins.
3. Where neither side is trustworthy, the shader blends A and B in place.

MetalFX spatial upscaling, when enabled, runs after this, on the frame that will be shown.

## What it cannot do

- Motion larger than roughly 45 pixels per capture on a small object is often missed. Those pixels fall back to a blend.
- The picture trails the source by roughly one capture interval plus about 25 ms. That delay is what makes the in-between frames possible.
- A window that stops drawing while it is covered will not be interpolated, because there is no new frame to interpolate from. Video playback continues under the overlay; page animations may not.

## Checks used while building 1.3

On an M1 Pro, with a 24 fps source and the Anime profile (capture cap 30, generation 4×):

| | Before the timestamp fix | 1.3 |
|---|---|---|
| Gaps between captured frames | 33, 33, 33, 67 ms | 41–42 ms |
| Frames that reached the display | 112–116 per second | 118–120 per second |
| Average error of one motion step | 2–3 ms | 0.4–1.2 ms |

Offline, against a frame rendered at the true halfway point, a 40 px object move scored 33.3 dB with the 1.3 pipeline, 29.4 dB with the previous flow, and 25.9 dB for a plain crossfade. Higher is closer to the true frame.
