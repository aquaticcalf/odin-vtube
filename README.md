# OdinVTube

A **clean-room, fully local** VTuber avatar runtime written in [Odin](https://odin-lang.org/) + [raylib](https://www.raylib.com/).

Inspired by public VTube Studio ideas (parameter names from `.vtube.json`, input→output mapping + smoothing, localhost plugin API shapes) — but **original code**, no Steam, no cloud, no telemetry, **no watermark**.

## Why this exists

VTube Studio’s webcam watermark is paid DLC. We won’t crack that.  
This project reimplements the *features you need* under your own license.

## Features (v0.1)

| Feature | Status |
|--------|--------|
| Local-only (no Steam / no company servers) | Yes |
| No watermark | Yes |
| Mouse face tracking | Yes |
| Idle / demo tracking modes | Yes |
| Keyboard mouth / smile / brows / roll | Yes |
| Auto blink + breath | Yes |
| VTS-style param mapping + smoothing | Yes |
| Procedural layered avatar | Yes |
| Custom avatar JSON + optional PNG billboard | Yes |
| Spring physics (hair / lag) | Yes |
| Expressions (happy/angry/sad/shock) | Yes |
| Hotkeys | Yes |
| OBS chroma key (green) | Yes |
| Localhost plugin API (TCP JSON lines) | Yes |
| Full Live2D `.moc3` mesh deform | **Not yet** (needs Cubism SDK) |
| Real webcam ML face track | **Stub** (mouse for now; OpenSeeFace later) |
| Spout / virtual cam | Not yet |

## Repo

```text
https://github.com/aquaticcalf/odin-vtube
```

## Build

Requires [Odin](https://odin-lang.org/) with `vendor:raylib` (included with Odin).

```bat
cd odin-vtube
build.bat
```

Or:

```bat
odin build . -out:odin-vtube.exe
```

Run **from this folder** so `assets/` and `configs/` resolve:

```bat
odin-vtube.exe
```

## Personal face training (Colab)

See [`personal_face/README.md`](personal_face/README.md) and  
[`personal_face/notebooks/Personal_Face_Train_Colab.ipynb`](personal_face/notebooks/Personal_Face_Train_Colab.ipynb).

The notebook clones this GitHub repo and trains a tiny you-only ONNX model.

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
| F2 / F3 / F4 | Mouse / Idle / Demo tracking |
| P | Toggle physics |
| Ctrl+C | Chroma key background |
| Ctrl+R | Reset pose |
| Esc | Quit |

## Config

`configs/default.json`:

- `tracking_mode`: `"mouse"` | `"idle"` | `"demo"`
- `chroma_key`: green screen for OBS
- `api_enabled` / `api_port`: localhost plugin server (default `8001`)
- `model_path`: avatar JSON

## Avatar format

See `assets/models/default/avatar.json`.

- Procedural `kind`: `head`, `body`, `hair`, `eye_l`, `eye_r`, `mouth`, `brow_l`, `brow_r`, `blush`
- Optional `image`: full-character PNG billboard (can point at a VTS texture for a static art base; mesh deform is not Live2D)
- Layer params use Live2D-style names: `ParamAngleX`, `ParamMouthOpenY`, …

## Plugin API (localhost only)

TCP `127.0.0.1:8001`, **one JSON object per line**.

Message envelope (VTS-public-API inspired):

```json
{"apiName":"OdinVTubeLocalAPI","apiVersion":"1.0","requestID":"1","messageType":"APIStateRequest","data":{}}
```

Supported `messageType` values:

- `APIStateRequest`
- `StatisticsRequest`
- `AuthenticationRequest` / `AuthenticationTokenRequest` (always approved locally)
- `InputParameterListRequest`
- `Live2DParameterListRequest`
- `InjectParameterDataRequest`
- `CurrentModelRequest`
- `HotkeyListRequest`

Example inject (PowerShell / any TCP client):

```json
{"apiName":"OdinVTubeLocalAPI","apiVersion":"1.0","requestID":"2","messageType":"InjectParameterDataRequest","data":{"parameterValues":[{"id":"MouthOpen","value":1.0,"weight":1.0}]}}
```

**Never binds to public interfaces** — only `127.0.0.1`.

## Relation to VTube Studio assets

You may **learn** parameter names and mapping ranges from public `.vtube.json` / docs.  
Do **not** copy proprietary binaries, Live2D moc3 runtime, or paid DLC logic into this tree.

Full Live2D support would require the official [Cubism SDK](https://www.live2d.com/) under Live2D’s license — a future optional module.

## License

Your project / your code in this folder. Do what you want with *this* codebase.
