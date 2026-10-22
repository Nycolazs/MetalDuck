# Release Process

## Build release artifact

```bash
bash scripts/create_release.sh
```

Generated artifact:
- `dist/MetalDuck-1.3.dmg`

DMG contents:
- `MetalDuck.app`
- `Applications` shortcut (drag-and-drop install flow)

## Publish to GitHub Releases

Example:

```bash
git tag -a v1.3 -m "MetalDuck v1.3"
git push origin main --tags

gh release create v1.3 \
  dist/MetalDuck-1.3.dmg \
  --title "MetalDuck 1.3" \
  --notes-file CHANGELOG.md
```

## Minimal release notes template

- Summary of feature improvements
- Known limitations
- Installation/run instructions
- Validation workflow (30->60 and upscale checks)
