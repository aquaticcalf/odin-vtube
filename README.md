# OdinVTube

**OdinVTube** is a lightweight, open-source avatar runtime for desktop.  
It is written in [Odin](https://odin-lang.org/) and rendered with [raylib](https://www.raylib.com/).

The goal is a small, understandable stack you can run fully offline: track motion into parameters, map those to an avatar, and stream or capture the result (for example with OBS chroma key).

Repository: [github.com/aquaticcalf/odin-vtube](https://github.com/aquaticcalf/odin-vtube)

---

## What it does

- Desktop window for a 2D avatar (procedural layers or optional PNG)
- Tracking inputs → smoothed model parameters (head, eyes, mouth, brows, breath)
- Mouse, idle, and demo tracking modes; keyboard for expression control
- Simple spring-style secondary motion
- Built-in expressions and hotkeys
- Optional green-screen background for OBS
- Local plugin API on `127.0.0.1` (JSON over TCP)
- Optional **personal face model** training pipeline (MediaPipe teacher → small ONNX student)

It is intentionally minimal. Full Live2D Cubism mesh support is not included yet; that would use the official [Live2D Cubism SDK](https://www.live2d.com/) under Live2D’s terms.

---

## Features (v0.1)

| Area | Status |
|------|--------|
| Offline desktop runtime | Supported |
| Mouse / idle / demo tracking | Supported |
| Keyboard mouth, smile, brows, roll | Supported |
| Auto blink and breathing | Supported |
| Parameter mapping and smoothing | Supported |
| Procedural layered avatar | Supported |
| Avatar JSON + optional billboard image | Supported |
| Secondary motion (springs) | Supported |
| Expressions and hotkeys | Supported |
| OBS-friendly chroma background | Supported |
| Localhost plugin API | Supported |
| Personal face ONNX training (Colab) | Supported (see `personal_face/`) |
| Webcam ML tracking at runtime | In progress (mouse first; ONNX next) |
| Live2D `.moc3` rendering | Planned (Cubism SDK) |
| Spout / virtual camera | Planned |

---

## Build

You need the [Odin compiler](https://odin-lang.org/) with the bundled `vendor:raylib`.

```bat
cd odin-vtube
build.bat
```

Or:

```bat
odin build . -out:odin-vtube.exe
```

Run from this directory so `assets/` and `configs/` resolve:

```bat
odin-vtube.exe
```

---

## Controls

| Input | Action |
|-------|--------|
| Mouse move | Look / head angles |
| Space | Mouth open |
| S | Smile |
| W | Brows up |
| Q / E | Head roll |
| B | Blink |
| Scroll wheel | Scale avatar |
| 1 / 2 / 3 / 4 | Expressions |
| 0 | Clear expressions |
| F1 | Toggle HUD |
| F2 / F3 / F4 | Mouse / idle / demo tracking |
| P | Toggle physics |
| Ctrl+C | Chroma key background |
| Ctrl+R | Reset pose |
| Esc | Quit |

---

## Configuration

Edit `configs/default.json`:

| Key | Meaning |
|-----|---------|
| `tracking_mode` | `"mouse"`, `"idle"`, or `"demo"` |
| `chroma_key` | Green background for OBS |
| `api_enabled` / `api_port` | Local plugin server (default `8001`) |
| `model_path` | Avatar definition JSON |
| `avatar_scale` | Base scale |
| `bg_color` | Window clear color (RGBA) |

---

## Avatar format

See `assets/models/default/avatar.json`.

- Procedural layer kinds: `head`, `body`, `hair`, `eye_l`, `eye_r`, `mouth`, `brow_l`, `brow_r`, `blush`
- Optional `image` for a full-character PNG
- Layers can bind to parameters such as `ParamAngleX`, `ParamMouthOpenY`, and similar names used widely in Live2D-style rigs

---

## Local plugin API

The server listens only on **`127.0.0.1`** (never on the public network by default).

Protocol: one JSON object per line over TCP (default port `8001`).

```json
{
  "apiName": "OdinVTubeLocalAPI",
  "apiVersion": "1.0",
  "requestID": "1",
  "messageType": "APIStateRequest",
  "data": {}
}
```

Supported message types include:

- `APIStateRequest`
- `StatisticsRequest`
- `AuthenticationRequest` / `AuthenticationTokenRequest`
- `InputParameterListRequest`
- `Live2DParameterListRequest`
- `InjectParameterDataRequest`
- `CurrentModelRequest`
- `HotkeyListRequest`

Example parameter inject:

```json
{
  "apiName": "OdinVTubeLocalAPI",
  "apiVersion": "1.0",
  "requestID": "2",
  "messageType": "InjectParameterDataRequest",
  "data": {
    "parameterValues": [
      { "id": "MouthOpen", "value": 1.0, "weight": 1.0 }
    ]
  }
}
```

---

## Personal face training

Train a small face model on **your own** footage (optional).

- Full guide (including **exact video checklist and durations**):  
  [`personal_face/README.md`](personal_face/README.md)
- Colab notebook:  
  [`personal_face/notebooks/Personal_Face_Train_Colab.ipynb`](personal_face/notebooks/Personal_Face_Train_Colab.ipynb)

### Video you need (summary)

| | |
|--|--|
| **Length** | **20–30 minutes** recommended (15 min minimum, 40 min excellent) |
| **Format** | MP4 H.264, 720p or 1080p @ 30 fps |
| **Where** | `Google Drive/odin_face/videos/*.mp4` |

Film **yourself** doing all of these (see the full table in `personal_face/README.md`):

1. Neutral face (~1–2 min)  
2. **Talking** while looking at cam (~5–8 min) — most important  
3. Mouth open/close (~1–2 min)  
4. Smile / laugh (~1–2 min)  
5. Blinks + hold eyes closed (~1–2 min)  
6. Look left / right (~1–2 min)  
7. Look up / down (~1–2 min)  
8. Head tilt / roll both ways (~1–2 min)  
9. Talk while turning head (~2–3 min)  
10. Raise brows / slight frown (~1–2 min)  
11. Lean closer / farther (~1 min)  
12. Optional: ¾ side views, dimmer lighting  

Use normal desk lighting and the same glasses setup you will use live.

### Face Recording Coach (no OBS)

Users do not need OBS. Open the guided recorder:

- Folder: [`personal_face/recorder/`](personal_face/recorder/)
- Windows: double-click `personal_face/recorder/open_recorder.bat`
- Or open `personal_face/recorder/index.html` in Chrome / Edge

It shows each step on screen, records your webcam, and lets you download the file for Drive / Colab.

The Colab notebook clones this repo, labels video with MediaPipe, trains a compact student network, and exports ONNX to Google Drive.

---

## Project layout

```text
odin-vtube/
  main.odin, *.odin     # runtime
  assets/               # default avatar
  configs/              # app settings
  personal_face/        # training pipeline (Python + Colab)
  build.bat
```

---

## License

This project is licensed under the [MIT License](LICENSE).

Third-party libraries (raylib, MediaPipe, OpenCV, Live2D Cubism if added later, etc.) keep their own licenses.
