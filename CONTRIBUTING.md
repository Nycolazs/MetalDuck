# Contributing to MetalDuck

First off, thank you for considering contributing to MetalDuck! It's people like you that make the macOS gaming community better.

## 🛠 Setup

MetalDuck requires **macOS 15.0+** and **Xcode 16+**.

```bash
# Clean and build
swift build -c release

# Run the binary
.build/release/MetalDuck
```

## 📐 Architecture Guidelines

To keep the project maintainable and professional, please follow these guidelines:

- **Modular Design**: Keep code grouped by feature area (`Capture`, `Rendering`, `Upscaling`, `FrameGeneration`, `App`).
- **Safety First**: Prefer explicit error handling and clear fallback paths (especially for Metal resource creation).
- **Performance**: Avoid expensive operations on the main thread. Core render logic should be optimized for frame latency.
- **Accuracy**: Ensure HUD labels and telemetry accurately reflect runtime behavior.

## 🤝 Pull Requests

1.  **Search**: Check for existing Issues or PRs before starting work.
2.  **Branch**: Create a feature branch for your changes.
3.  **Template**: Fill out the provided PR template in detail.
4.  **Style**: Maintain consistency with the existing Swift style (4 spaces, descriptive naming).

## 💬 Community

If you have questions or want to discuss a major change, please open an **Issue** first. We value clear communication and stable progress.

---
*By contributing to MetalDuck, you agree that your contributions will be licensed under its MIT License.*
