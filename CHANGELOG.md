# Changelog

All notable changes to the MetalDuck project will be documented in this file.

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
