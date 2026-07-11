# Making models (Krita, Paint, free format)

OdinVTube does **not** need Live2D Cubism.  
You draw PNGs in any paint program, then import them in the **model editor (F5)**.

---

## Ideal workflow (recommended): **Krita**

Krita is free and supports **layers** — best match for VTuber-style parts.

### 1. Draw in layers

Create one layer (or group) per part, named clearly:

| Layer name | Becomes |
|------------|---------|
| `body` | body part |
| `head` | head |
| `hair` | hair |
| `eye_l` / `eye_r` | eyes |
| `brow_l` / `brow_r` | brows |
| `mouth` | mouth |
| `blush` | blush |
| `full` / `character` / `avatar` | **full-body billboard** (single image) |

Tips:

- Transparent PNG background  
- Keep the character roughly centered  
- Canvas ~1000–2000 px tall is plenty  
- Eyes/mouth as separate layers if you want them to move with tracking  

### 2. Export layers as files

In Krita:

1. **Layer → Import/Export → Save Group Layers…**  
   or export each layer visible alone as PNG  
2. Save into a folder, e.g.  
   `assets/models/my_avatar/textures/`  
   with names like `head.png`, `eye_l.png`, …

### 3. Import into OdinVTube

1. Run OdinVTube → press **F5** (editor)  
2. Either:  
   - **Drag and drop** the PNG files onto the window, or  
   - Put them in `assets/models/import/` or next to your model under `textures/` and click **Import folder**  
3. Drag parts into place, bind head/body motion  
4. **Ctrl+S** to save  

**Shift + drop** a PNG replaces the **selected** layer’s art (keeps position).

---

## Simple workflow: **MS Paint** (or any single-image tool)

Paint is fine for a **simple** avatar:

1. Draw your whole character  
2. Save as **PNG** (not JPEG if you need transparency — Paint’s PNG is OK for opaque; for transparent use Paint 3D / Krita / Photopea)  
3. Name it e.g. `full.png` or `character.png`  
4. **F5** → drop the file onto OdinVTube  
5. It becomes a **billboard** (full image that still turns a bit with head tracking)  
6. Optionally add procedural eyes/mouth on top with **Add part**  

Or export several PNGs (`head.png`, `body.png`) from Paint one at a time by copy-pasting parts — clunky but works.

---

## Naming cheatsheet

Filenames are auto-detected (case-insensitive):

```text
head.png       → head + head tracking binds
hair.png       → hair
body.png       → body
eye_l.png      → left eye
eye_r.png      → right eye
mouth.png      → mouth
brow_l.png     → left brow
full.png       → full-body billboard
anything_else  → generic sprite layer
```

---

## Project layout after import

```text
assets/models/default/
  avatar.json          ← model definition (saved by editor)
  textures/
    head.png
    eye_l.png
    mouth.png
    ...
```

Share the whole folder — paths are relative.

---

## What not to worry about

| Not needed | Why |
|------------|-----|
| Live2D Cubism | We use free layered PNGs |
| PSD import | Export PNG layers instead |
| Perfect mesh deform | Soft 2D moves via params is enough for v1 |

---

## Quick start

1. Open **Krita** → draw layers → export PNGs  
2. OdinVTube **F5** → **drop PNGs**  
3. Arrange → **Ctrl+S**  
4. **F5** leave editor → **F9** for OBS  
