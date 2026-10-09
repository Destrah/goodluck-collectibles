# Vending cylinder lock texture

The original 2048×2048 atlas is preserved outside the 44-pixel cylinder lock at atlas center (554,365). The lock artwork was generated using the built-in imagegen tool, then only that circular detail was composited onto the original to preserve the UV layout and all other artwork.

Prompt: Add one small front-facing circular brushed silver cabinet cylinder lock with a dark vertical key slot in the blank purple area right of COINS/TOKENS, below $1 and above the cyan keypad divider. Preserve the existing atlas, graphics and text; no labels or annotations.

`vending_basecolor_nopacks_2048_lock.png` is the edited source. `vending_basecolor_nopacks_2048_lock.dds` matches the original DXT1 format with 12 mip levels. The workspace's `fivem/stream/metacomics_vending_shared.ytd` has already been updated; deploy it with `fivem/config.lua` and `fivem/client/vending_crime.lua`. No Blender/YDR re-export is required. A backup of the previous shared YTD is retained here.

For future OpenIV replacement, retain the existing diffuse texture entry name rather than adopting the `_lock` filename as the entry name.

Crime.BreakIn.Interaction and Crime.PickPadlock.Interaction control approach positions and facing targets in machine-local coordinates. Front is negative Y; these defaults align with the current atlas cylinder and configured external padlock. Final animation/tool placement should be checked in FiveM with the player's ped model.
