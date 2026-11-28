# Changelog

All notable changes to the MetalDuck project will be documented in this file.

## [1.4.0] - unreleased

Not yet run end to end: this version builds and its tests pass, but the picker, the manual resolution controls and the placements still need trying on real windows before release.

### Added
- **Choose the source in the macOS picker.** The Choose button opens the system's own window, app and display picker. Choosing an app scales its main window. Choosing again while scaling runs switches the source without stopping. Start with nothing chosen opens the picker first, and the last app and window are remembered.
- **Native resolution: frame generation without scaling.** Native captures the source at its own size and skips the scaler, so the picture is as sharp as the source. The Anime and Video profiles now use it. Auto still captures within about 1920×1080 worth of pixels and scales up, which is cheaper and softer on a large window; Games keeps Auto.
- **Manual input and output resolution.** Manual takes an input size, which the source is captured and processed at, and an output size, which the picture is scaled to, both in pixels, with presets. Aspect chooses between bars, cropping and stretching when the shapes differ.
- **Placement.** In Manual, the picture can stay over the source, sit centred at the output size, or fill the display, so a small window can be shown large. The overlay still never takes clicks: away from the source they go to whatever is under the pointer.
- A test target and a CI workflow. `swift test` covers frame timing, the size and placement arithmetic, and how saved settings load.

### Changed
- **Requires macOS 15.2**, for the picker.
- Fit to output and Scale factor are gone. With Fit on, as in every built-in profile, the factor did nothing. Saved profiles load as Automatic.
- Dynamic resolution now follows GPU time and lowers the capture size, where frame generation's cost is. It used to follow the display's own beat, which barely moves, and only shrank the final resize.
- Capture size, cursor and queue depth change on the running stream instead of restarting it.
- The app is split into a library and a small executable, and `Present.metal` is bundled as source, so building no longer needs the Metal Toolchain.
- `scripts/create_release.sh` signs with the hardened runtime and notarizes when given a Developer ID and a notary profile.

### Fixed
- **A profile's capture settings did not reach the stream.** The capture rate, queue depth and cursor setting only took effect after one of those controls was moved, and the capture size changed when one was. There is now one capture configuration, applied whenever a profile is picked and before each start.
- **Setting changes were not saved.** Changes to your own profiles are now saved as you make them. A changed built-in profile is marked, and `+` saves what is on screen.
- **Refresh changed the selected window.** The lists keep the selection by identifier and no longer jump to a browser window.
- **A pointless resample on every frame.** At the source's own size the picture went through the scaler to lose a few pixels. A target within 1% of the input now skips it.
- **The picture drifted from a window at the screen's edge.** A window partly off screen or under the Dock was squeezed into the part that showed. The overlay now shows exactly the part it covers.
- The Source row of the stats overlay now shows what the source sends, before repeats are skipped and the cap is applied, so its throttling hint can appear.
- A small source is no longer captured at more pixels than it has.

### Removed
- "MetalFX Temporal", which always ran the spatial scaler. Saved profiles load it as Spatial.
- The Accessibility permission prompt at launch. Nothing used it.
- The stall recovery that could never run, the Core Graphics window list, code paths for macOS 14 and earlier, and the cut-down fallback shader. A missing shader file now fails at launch with a message.

## [1.3.2] - 2026-11-21

Bug fixes for frame generation on full-screen video, found while watching films, trailers and anime with the Anime profile (30 fps capture, 4x, 120 Hz).

### Fixed
- **Lag and input delay.** Frames are now drawn on a render thread of their own, paced by `CAMetalDisplayLink`, so the main thread can no longer hold up the picture. The overlay stays hidden until the first frame is drawn, which fixes the black screen on Start and after Stop.
- **Uneven motion on browser video.** Browsers repaint more often than the video changes (Firefox sent over 60 frames a second for a 24 fps trailer). Repeated pictures are now skipped, frames are placed on the video's steady beat, and the capture rate is applied on average, so 24 fps video stays evenly spaced.
- **Mismatched frames at scene cuts.** Pairs of frames with nothing in common (cuts, flashes, jumps) are detected from the motion search and no frames are built between them. Flow is never borrowed across a cut.
- **See-through copies of fast objects.** Vision's flow barely sees an object crossing a still background. A block search on the GPU now follows moves up to about 320 px between frames, and uses them only where Vision is clearly wrong.
- **Halos and ghost edges around people and other large moving objects, at any speed.** In-between frames now carry the motion of both captures to the moment being built (splatting), so each spot knows which capture sees it. Background a person has just uncovered is no longer dragged along with them. On a test with a large walking figure the figure area improved by 2.5 to 3 dB, and real footage improved in all 18 tests. Cost: about 0.4 ms of GPU per in-between frame.
- **Block-shaped tears next to fast objects.** The check that lets a pixel use a nearby block's motion is stricter, and a block's motion no longer replaces the main motion unless that clearly fits better.
- **Tears and doubling in fast action and anime.** New Artifact guard setting (Off, Balanced, Strong) in the Frame Generation panel. For each pair, the GPU measures how much of the picture no known motion fits, and draws the hard pairs closer to the nearest real frame. Normal footage is not affected. Balanced is the default; Profiles saved earlier load with it on.

### Interface
- The Frame Generation panel has the Artifact guard row. The two columns of the control panel keep their own height, so the group titles no longer drift.
- The Monitor log records the artifact guard level, how hard each pair was, and how far it was calmed.

## [1.3.1] - 2026-11-20

### Interface
- The Monitor is now a page inside the main window instead of a separate sheet. Click Monitor in the sidebar, then click it again or press Esc to return. It only updates while it is showing.
- New silver duck app icon, and a redesigned installer disk image with a dark window, a background, a volume icon and a fixed layout.
- Opening the sidebar slides it on Core Animation: the layout is computed once and the layers move, so it no longer re-lays out the window on every frame. The header and the page are pushed aside, never covered.
- Switches rebuilt with layers: the knob slides on a spring and stretches while pressed. The segmented control pill, sidebar selection and entrance animations moved to Core Animation too.
- Clicks on controls no longer start a window drag.

### Performance
- Opening and closing the sidebar costs about 160-180 ms of main-thread time for three cycles, down from about 1,000 ms.
- Picking a profile reuses the sidebar rows instead of rebuilding them. Slider drags no longer re-apply every control, and capture reconfiguration runs one at a time with the latest values.
- The overlay render loop pauses while nothing is running instead of drawing at up to 120 fps.
- The Monitor's event log no longer loads the spell checker on first open, which caused a 66 ms hitch.

### Release tooling
- `scripts/create_release.sh` takes the version from `VERSION` (default 1.3.1) and writes it into the app, the disk image name, and the installer background.
- `scripts/generate_brand_assets.swift` regenerates the icon and the installer backgrounds from `Designs/MetalDuck_Logo_Silver.png`. `DMG_THEME=light` builds the light installer.

## [1.3] - 2026-10-22

### Frame generation
- Rewrote interpolation around Vision optical flow revision 1. Vectors are in pixels and a pair is ready in about 20 ms, so the frame on screen is built from the pair it sits between.
- Output follows capture timestamps and trails the source by about one capture interval. 24 fps video stays evenly spaced under a 30 fps capture cap.
- One compute kernel, `flowInterpolate`, warps both captures and rejects vectors that do not survive a round trip through the opposite field.
- The configured capture rate and queue depth are applied to the ScreenCaptureKit stream.

### Interface
- Rebuilt the control panel, added the in-app guide, the menu-bar controls, and the activity monitor.

### Removed
- The per-capture motion estimator. Nothing in the pipeline read its result.
- The Core Graphics capture fallback. MetalDuck requires macOS 15, where ScreenCaptureKit is always available.
- The unused hook for game-provided depth and motion textures.

## [1.2.0] - 2026-03-17

This release marks a major milestone in MetalDuck's evolution, focusing on **high-performance Frame Generation algorithms**, professional branding, and a refined installation experience.

### 🚀 Frame Generation & Core Engine
- **Optical Flow Optimization**: Upgraded to `.high` accuracy in Vision flow requests, significantly improving motion vector estimation for complex scenes.
- **Improved Resolution**: Increased flow computation resolution to 1280px (previously 640px) to better capture large displacements in low-framerate content like 24fps anime.
- **Seamless Interpolation**: Refined `flowWarp` and `flowCompose` shaders to reduce "ghosting" and artifacts during fast-moving sequences.
- **MetalFX Synergy**: Optimized the pipeline for deeper integration with MetalFX spatial upscaling, ensuring a stable and flicker-free presentation.

### ✨ Added
- **New Branding**: Complete refresh of the application logo and iconography (V4 design).
- **Profile Management System**: Create, rename, duplicate, and delete custom configuration profiles.
- **Global Shortcuts**: Support for global keyboard shortcuts to toggle scaling (`CMD+S` by default).
- **Professional DMG**: Standard macOS DMG installer layout for a native distribution feel.

### 🛠 Fixed
- **UI Stability**: Resolved issues with section overlaps and inconsistent layout behavior.
- **Build Process**: Streamlined the `create_release.sh` script to produce clean, versioned DMG files.
- **Redundant UI**: Removed legacy sections to focus on core performance controls.

### 🧹 Improved
- **Installer Layout**: Perfected icon alignment and window bounds for the DMG installer.
- **Documentation**: Overhauled `README.md` for better clarity and professional appeal.

---

*For more details on specific features, refer to the documentation in `docs/`.*
