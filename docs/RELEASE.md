# Release Process

## Build release artifact

```bash
bash scripts/create_release.sh
```

Generated artifact:
- `dist/MetalDuck-macos-arm64.dmg`

DMG contents:
- `MetalDuck.app`
- `Applications` shortcut (drag-and-drop install flow)

## Publish to GitHub Releases

Example:

```bash
git tag -a v0.1.0 -m "MetalDuck v0.1.0"
git push origin main --tags

gh release create v0.1.0 \
  dist/MetalDuck-macos-arm64.dmg \
  --title "MetalDuck v0.1.0" \
  --notes-file docs/RELEASE_NOTES_v0.1.0.md
```

## Minimal release notes template

- Summary of feature improvements
- Known limitations
- Installation/run instructions
- Validation workflow (30->60 and upscale checks)
