# Rush Trading Cards — Standalone React Lab v3

Standalone browser test app derived from your FiveM trading-card resource.

## Run locally

```powershell
npm install
npm run dev
```

Open the Vite URL (normally `http://localhost:5173`).

## What changed in v3

### 1) Subject outline / masking kept and improved
The selective subject system is still in the app and is now more visible for outline-style finishes.

Each **print variant** can have any number of **subject layers**. Every layer can have its own:

- transparent PNG/WebP subject image
- effect mode
- effect strength
- foil colors

Subject modes included:

- Rainbow outline
- Gold outline
- Silver outline
- Rainbow subject foil
- Prism subject foil
- Etched subject foil
- Cosmos subject foil

Outline modes now render with an additional glow layer so they read more like an actual chase-outline treatment rather than looking like the effect disappeared behind the artwork.

### 2) Full-card holo strength slider retained
Every print variant still has a **Holo strength** slider from `0–100` so effects like rainbow foil can be toned down and not wash out the artwork.

### 3) Large single-card viewer
In the **Pack / box lab**, clicking a hidden card reveals it.

Clicking the **revealed** card again opens a larger centered viewer with a short motion animation from the card's pack position into the middle of the screen.

### 4) Idle white highlight removed
The little white glare/light spot is no longer visible when a card is just sitting still.

It now only appears while hovering over interactive cards.

Also, cards shown in revealed pack slots are rendered with `interactive={false}`, so after flipping they do **not** tilt or move the foil around when hovered.

### 5) Pack and box animations updated
The pack/box lab now uses your uploaded **Meta Comics** artwork by default:

- `public/img/meta_pack.png`
- `public/img/meta_box_sheet.png`

It also adds simple animation layers for:

- pack rip / tear
- box cellophane unwrap
- box opening
- visible packs peeking out of the opened box

### 6) Pack / box sound effects updated
The pack and box sounds are generated with the **Web Audio API**.

They are not studio-recorded samples, but they now distinguish between:

- **pack rip / cardboard-like tear**
- **box cellophane / plastic crinkle**
- **box reveal**
- **deal**
- **flip**
- **rare reveal chime**

### 7) Uploaded FiveM stream props included as references
Your uploaded `stream.zip` has been copied into:

```text
reference/fivem-stream/
```

That includes:

- `prop_boosterpack_01.ydr`
- `prop_boosterbox_01.ydr`
- `prop_deckbox_01.ydr`
- `booster_props.ytyp`
- `prop_deckbox_01.ytyp`

A browser still cannot render `.ydr/.ytyp` directly. The React lab will only render the actual 3D prop if you convert/export the relevant model to GLB and place it at:

```text
public/models/prop_boosterpack_01.glb
public/models/prop_boosterbox_01.glb
```

If those files are missing, the app falls back to the uploaded artwork PNGs.

## How to make the transparent subject PNG correctly

The biggest rule is:

**Do not crop the transparent file around the person.**

If your original artwork is `1920x1080`, your transparent subject file should also be `1920x1080`.

Keep the character in the exact same position. Remove the background, but keep the canvas size unchanged.

### Photoshop / Photopea workflow

1. Open the full artwork.
2. Select the character or object.
3. Remove or hide everything else.
4. **Do not trim/crop the transparent space away.**
5. Export as PNG or WebP with transparency.

### Good example

- Original art: `1920x1080`
- Transparent subject PNG: `1920x1080`
- Character is still in the same position

### Bad example

- Original art: `1920x1080`
- Transparent subject PNG: `700x900` tightly cropped around the person

That tightly cropped version loses the original positioning, so it will not line up correctly.

## How to do multiple versions of subject-outline / subject-foil effects

This is handled per **print variant**.

Example setup for one character:

- **Base print**
  - no subject layer
  - no full-card holo
- **Reverse holo print**
  - reverse holo on full card
- **Gold outline print**
  - subject layer using character cutout
  - mode = `outline-gold`
- **Prism subject foil print**
  - different subject image if desired
  - mode = `foil-prism`
- **Chase print**
  - full-card holo + one or more subject layers stacked together

Because each print variant stores its own:

- artwork override
- full-card holo
- holo strength
- subject layers
- subject colors

...you can create multiple versions of the same character with different masking/outline treatments.

You can also stack **multiple subject layers on a single print**. Example:

- layer 1 = character outline gold
- layer 2 = weapon prism foil
- layer 3 = badge rainbow foil

Each can use a different transparent image.

## Reverse holo note

The reverse-holo effect still uses the structural fix from v2:

- the artwork window sits above the reverse foil layer
- the effect no longer relies on hard-coded coordinates for the picture cutout

That means the picture portion stays aligned at different card sizes.

## Data persistence

Changes are stored in browser `localStorage` under a **v3** key.

Large base64 images can eventually exceed localStorage limits, so use **Export JSON** for anything you want to keep.
