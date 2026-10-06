# Meta Comic Collectibles v5.0 — Standalone + modular FiveM progressive drop-in

Drop these files over the current React project.

## Main architecture change
The React application is now the base product and can run in two environments:

- normal browser/Vite standalone mode
- FiveM NUI mode

React components no longer need to know about QBCore/Qbox directly.

## New React runtime layer
Added:

```text
src/runtime/
  env.js
  packLogic.js
  bridge/
    index.js
    standalone.js
    fivem.js
  storage/
    index.js
    standalone.js
    fivem.js
```

`App.jsx` now loads/saves cards through the storage adapter.
`PackSimulator.jsx` opens packs through the runtime bridge.

In standalone mode pack rolls still happen locally.
In FiveM mode pack rolls happen server-side and the NUI only renders the returned result.

## FiveM integration added
New `fivem/` folder with:

- standalone framework adapter
- QBCore adapter
- Qbox adapter
- custom framework template
- no-inventory adapter
- QBCore inventory adapter
- ox_inventory adapter
- none / JSON / MySQL / custom persistence adapters
- server-authoritative pack roll logic
- NUI RPC bridge
- client commands and exports
- physical pack/box prop animations
- generated authoritative card catalog
- optional owned-card MySQL schema

## FiveM 3D assets restored
Included directly under `fivem/stream/`:

- booster pack YDR
- booster box YDR
- deck box YDR
- YTYP files

The original DDS source textures are also included.

## Build commands
Normal standalone build:

```powershell
npm run build
```

FiveM NUI build:

```powershell
npm run build:fivem
```

Regenerate FiveM card catalog:

```powershell
npm run catalog:fivem
```

See `fivem/README.md` for configuration examples.
