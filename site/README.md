# MetalDuck website

The landing page at https://metalduck-production.up.railway.app.

It is a small React app (Vite + TypeScript). The animated pieces come from
[React Bits](https://reactbits.dev); see `src/reactbits/NOTICE.md`. The demo near the top
(`src/FrameDemo.tsx`) draws a 24 fps source and the same motion with MetalDuck's
in-between frames, at the real rates.

## Run it locally

```bash
cd site
npm install
npm run dev
```

Then open http://localhost:4173.

## Deploy

The site is hosted on Railway. The `Dockerfile` builds the app and serves `dist/` with Caddy
on the port Railway provides.

```bash
cd site
railway up --service metalduck
```

## Updating for a new release

The version and download links are in `src/App.tsx` (`DOWNLOAD`, and the "Version 1.3.1"
text). The app screenshots in `public/assets/` come from
`scripts/generate_mac_mockups.swift` in the repository root.
