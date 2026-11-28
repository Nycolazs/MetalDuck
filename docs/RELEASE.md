# Release Process

## Build release artifact

```bash
bash scripts/create_release.sh
```

Generated artifact:
- `dist/MetalDuck-1.4.0.dmg` (set `VERSION` for another number)

## Signing and notarizing

By default the script signs ad hoc. That is enough to run the app on the Mac that built
it, but macOS ties Screen Recording permission to the signature, so each new ad hoc build
asks for it again, and Gatekeeper warns when the app is opened on another Mac.

For a build other people install, sign with a Developer ID and notarize:

```bash
# Once: store notary credentials in the keychain under a profile name.
xcrun notarytool store-credentials metalduck-notary \
  --apple-id "<apple id>" --team-id "<team id>" --password "<app-specific password>"

CODESIGN_IDENTITY="Developer ID Application: <name> (<team id>)" \
NOTARY_PROFILE=metalduck-notary \
bash scripts/create_release.sh
```

With `CODESIGN_IDENTITY` set, the app is signed with the hardened runtime and a
timestamp, and the disk image is signed. With `NOTARY_PROFILE` set as well, the disk image
is submitted to Apple, and the ticket is stapled to it.

The bundle identifier is `com.nycolazs.metaldduck` (in the script's `Info.plist`). Changing
it resets Screen Recording permission and saved profiles for everyone once, so decide on
it before the first Developer ID release and leave it alone afterwards.

DMG contents:
- `MetalDuck.app`
- `Applications` shortcut (drag-and-drop install flow)

## Publish to GitHub Releases

The release notes are the matching section of `CHANGELOG.md`, so the release page
always says what changed in that version:

```bash
VERSION=1.4.0
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
