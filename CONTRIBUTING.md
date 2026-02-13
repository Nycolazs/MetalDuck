# Contributing

## Setup

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift run
```

## Guidelines

- Keep code modular by feature area (`Capture`, `Rendering`, `Upscaling`, `FrameGeneration`, `App`).
- Prefer explicit error handling and clear fallback paths.
- Keep UI labels and telemetry accurate to runtime behavior.

## Pull requests

Please include:
- concise problem statement,
- implementation summary,
- validation steps,
- known limitations.
