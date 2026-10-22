# Changelog

All notable changes to the MetalDuck project will be documented in this file.

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
