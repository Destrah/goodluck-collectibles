Optional GTA prop -> web model support
=====================================

The original FiveM files are GTA V .ydr/.ytyp assets. Browsers cannot render those files directly.

To use the actual pack/box geometry in this standalone React test app:

1. Open/export the GTA prop with a GTA modding workflow such as CodeWalker and/or Blender + Sollumz.
2. Export the visible mesh/materials/textures to glTF/GLB.
3. Put the converted files here using these exact names:

   prop_boosterpack_01.glb
   prop_boosterbox_01.glb

The React app automatically checks for those files. If they exist it uses the rotatable 3D model; if they do not exist it falls back to the existing uploaded Meta Comics pack/box artwork PNGs.

Keep the original .ydr/.ytyp files in the FiveM resource for the in-game version. The conversion is only for the browser test lab.
