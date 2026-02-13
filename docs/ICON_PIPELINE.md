# Icon Pipeline

## Current icon assets

- Main PNG: `Sources/MetalDuck/Assets/AppIcon.png`
- ICNS package: `Sources/MetalDuck/Assets/AppIcon.icns`
- Iconset: `Sources/MetalDuck/Assets/AppIcon.iconset/`

## Transparent icon workflow

1. Generate/update base art (SVG or PNG).
2. Keep transparent background in final `AppIcon.png` (1024x1024).
3. Rebuild iconset and ICNS:

```bash
ICON_SRC=Sources/MetalDuck/Assets/AppIcon.png
ICONSET_DIR=Sources/MetalDuck/Assets/AppIcon.iconset
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for size in 16 32 64 128 256 512; do
  sips -z $size $size "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}.png"
  double=$((size*2))
  sips -z $double $double "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET_DIR" -o Sources/MetalDuck/Assets/AppIcon.icns
```

## Runtime icon assignment

`AppDelegate` calls:
- `NSApplication.shared.applicationIconImage = MetalDuckIcon.make()`

`MetalDuckIcon.make()` loads bundled `Assets/AppIcon.png` first.
