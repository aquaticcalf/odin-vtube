# OBS Studio setup (out of the box)

OdinVTube does **not** require Spout, NDI, or a virtual camera for a first working stream.  
Use **Window Capture + Chroma Key**.

---

## One-minute setup

### 1. Start OdinVTube OBS mode

In OdinVTube press **`F9`**.

That will:

- Switch to a **borderless** `1280×720` window  
- Title: **`OdinVTube OBS`** (easy to find in the capture list)  
- **Green** background (chroma key)  
- **Topmost** so it stays easy to grab  
- HUD hidden (press **F1** if you want it back)

Press **`F9` again** to leave OBS mode.

### 2. OBS Studio

1. Open **OBS Studio**  
2. **Sources → + → Window Capture**  
3. Window: **`[odin-vtube.exe]: OdinVTube OBS`** (wording may vary slightly)  
4. Uncheck “Capture Cursor” if you like  
5. Select the source → **Filters → + → Chroma Key**  
6. **Key Color Type:** Green  
7. Similarity / Smoothness: tweak until the green is clean  

Your avatar should sit over whatever is under that scene (game, BRB screen, etc.).

---

## Tips

| Tip | Detail |
|-----|--------|
| Resolution | OBS mode uses **1280×720**. Scale the source in OBS if needed. |
| Game Capture | Prefer **Window Capture** for this app. |
| Color spill | Raise **Key Color Spill Reduction** if green fringes remain. |
| Manual chroma | Without F9: **Ctrl+C** toggles green background anytime. |
| Editor | **F5** model editor; leave OBS mode first if the window looks odd. |

---

## What’s not required

- Paid SDKs  
- Spout / NDI plugins (optional later, not needed for basic streaming)  
- Virtual webcam for OBS (only if you want Discord/Zoom face cam separately)

---

## Optional later

- Spout2 sender for zero-chroma pipeline  
- Virtual camera for non-OBS apps  

Core path for most people: **F9 → Window Capture → Chroma Key**.
