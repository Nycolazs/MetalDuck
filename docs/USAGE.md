# Usage

The current walkthrough, with a picture of the window, is in the [README](../README.md#using-it).

Short version:

1. Launch MetalDuck and allow Screen Recording.
2. Pick a profile, or set capture, frame generation, and scaling yourself.
3. Choose a display or a window.
4. Press Start. The overlay follows the source and ignores clicks.
5. Stop from the button, the menu-bar icon, or the stop shortcut. Control-Option-Command-Escape always stops it.

Capture, Output, and Generated in the top row are the live rates. The built-in profiles are Games (60 fps, 2×), Anime (30 fps cap, 4×), and Video (30 fps cap, 2×).

## Turkish subtitles

On macOS 26 or later, open the MetalDuck menu-bar icon and choose the game's
text language under **Türkçe Altyazı**. The main window also has a **Türkçe Altyazı (OCR)** card with source language and scan area controls. The feature is off by default. In
**System Settings → General → Language & Region → Translation Languages**,
download Turkish and the selected source language. If prompted to download
languages while scaling, select the source language again after they install.
Available language pairs depend on the Apple Translation models on the Mac.

Start scaling with the game window or capture card selected. In the
**Türkçe Altyazı (OCR)** card or menu, choose **Alan seç…** and drag a
rectangle over the text in the capture preview. The selection is saved
relative to the frame. OCR reads only inside that rectangle, and waits for
a selection before scanning. Select **Alanı değiştir…** to draw it again.
Pick **Kapalı** to turn subtitles off. Recognition and translation run on
the Mac.

## Capture cards

Use the packaged **MetalDuck.app** with a USB capture card that macOS exposes
as an external video device (for example, a UVC HDMI capture card). Connect the
card and HDMI source, select **Card** under Capture Mode, refresh sources if
needed, and choose the device by name. You can also select a device from
**Capture Card** in the MetalDuck menu bar. Allow Camera access when macOS asks.
Start scaling as usual. The video opens on the control window's display and
uses the same upscaling, frame generation, and Turkish subtitle controls.

This captures video. Audio stays with your existing routing. The card supplies
the input format and frame rate. MetalDuck's capture FPS setting caps the rate
passed to the rendering pipeline.
