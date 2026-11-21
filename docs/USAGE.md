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
text language under **Türkçe Altyazı**. The feature is off by default. In
**System Settings → General → Language & Region → Translation Languages**,
download Turkish and the selected source language. If prompted to download
languages while scaling, select the source language again after they install.
Available language pairs depend on the Apple Translation models on the Mac.

Start scaling with the game window selected. MetalDuck reads text in the lower
40% of the capture and shows the Turkish translation along the bottom of the
overlay. Enable **Tüm Görüntüyü Tara** to include menus and text elsewhere in
the window. For display capture, this includes any other visible apps in the
scan area. Pick **Kapalı** to turn subtitles off. Screen recognition and
translation run on the Mac. Text and frames are held in memory during the session.
