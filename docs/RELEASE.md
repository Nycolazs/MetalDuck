# Release Process

## Build release artifact

```bash
bash scripts/create_release.sh
```

Generated artifact:
- `dist/MetalDuck-1.3.2.dmg`

DMG contents:
- `MetalDuck.app`
- `Applications` shortcut (drag-and-drop install flow)

## Publish to GitHub Releases

The release notes are the matching section of `CHANGELOG.md`, so the release page
always says what changed in that version:

```bash
VERSION=1.3.2
awk -v v="$VERSION" '/^## \[/{p=index($0,"["v"]")>0} p' CHANGELOG.md > /tmp/notes.md

git tag -a "v$VERSION" -m "MetalDuck v$VERSION"
git push origin main --tags

gh release create "v$VERSION" \
  "dist/MetalDuck-$VERSION.dmg" \
  --title "MetalDuck $VERSION" \
  --notes-file /tmp/notes.md
```

## Minimal release notes template

- Summary of feature improvements
- Known limitations
- Installation/run instructions
- Validation workflow (30->60 and upscale checks)
