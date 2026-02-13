# MetalDuck v0.1.1

## Packaging update

- Release asset is now distributed as a native macOS `.dmg` instead of `.zip`.
- Added/updated release tooling script to generate DMG directly.
- DMG now contains installer-style layout:
  - `MetalDuck.app`
  - `Applications` shortcut for drag-and-drop install.

## Included improvements

- Current capture + upscaling + frame-generation pipeline from `main`.
- Updated English documentation for build, release, and usage.

## Run after mounting DMG

1. Mount `MetalDuck-macos-arm64.dmg`.
2. Drag `MetalDuck.app` to `Applications`.
3. Open MetalDuck from `/Applications`.
