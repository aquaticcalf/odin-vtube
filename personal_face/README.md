# Personal face model training

Train a **small, efficient face model** on your own webcam recordings, then use the exported ONNX with OdinVTube.

Pipeline:

```text
Your MP4 videos
      ↓
label_teacher.py   (MediaPipe → face crops + tracking labels)
      ↓
samples.npz
      ↓
train_student.py   (tiny CNN)
      ↓
export_onnx.py
      ↓
personal_face_student.onnx
```

This is meant for a single person (you). A model specialized to one face can stay smaller and still look good.

---

## Layout

```text
personal_face/
  student/
    model.py          # TinyFaceStudent network
    geometry.py       # landmarks → head / eye / mouth params
  scripts/
    label_teacher.py
    train_student.py
    export_onnx.py
    infer_webcam.py   # optional local ONNX smoke test
  notebooks/
    Personal_Face_Train_Colab.ipynb
  requirements.txt
```

---

## Output parameters

The student predicts 11 values:

`FaceAngleX`, `FaceAngleY`, `FaceAngleZ`,  
`EyeOpenLeft`, `EyeOpenRight`, `EyeRightX`, `EyeRightY`,  
`MouthOpen`, `MouthSmile`,  
`BrowLeftY`, `BrowRightY`

These match the parameter names used by the OdinVTube runtime.

---

## Google Colab (recommended)

Repo: [github.com/aquaticcalf/odin-vtube](https://github.com/aquaticcalf/odin-vtube)

1. Upload face videos to Google Drive:  
   `MyDrive/odin_face/videos/*.mp4`
2. Open  
   `personal_face/notebooks/Personal_Face_Train_Colab.ipynb`  
   from GitHub in Colab
3. Set **Runtime → GPU**
4. Run all cells  

The notebook will:

- mount Drive  
- clone this repository  
- install dependencies  
- label, train, and export ONNX to  
  `MyDrive/odin_face/runs/run1/`

## What video to record (exact checklist)

You only need **your face**. One continuous recording is fine, or several clips that add up to the same total.

### Target length

| Goal | Total length |
|------|----------------|
| Minimum usable | **~15 minutes** |
| Recommended | **20–30 minutes** |
| Excellent | **30–40 minutes** |

Shorter than ~10 minutes will train, but tracking will look weaker.

### Camera & file settings

| Setting | Do this |
|---------|---------|
| Format | **MP4**, H.264 |
| Resolution | **720p or 1080p** |
| Frame rate | **30 fps** |
| Framing | Face fills about **40–70%** of the frame; shoulders OK |
| Distance | Normal desk / streaming distance (the one you will use later) |
| Lighting | **Your normal room/stream lights** — most important |
| Glasses | If you always wear them, film **with** glasses; if mixed, do **both** (~half each) |
| Upload path | `Google Drive/odin_face/videos/*.mp4` |

### Exact face actions (do all of these)

Work through the list slowly. Hold each pose a few seconds, then move smoothly. You can loop the list more than once.

| # | What to do | How long (about) | Why |
|---|------------|------------------|-----|
| 1 | **Neutral face**, look at camera | 1–2 min | Baseline |
| 2 | **Talk naturally** (read a script, chat, count 1–100) | **5–8 min** | Mouth while speaking (most important) |
| 3 | **Mouth open** wide, then closed — repeat | 1–2 min | Mouth open amount |
| 4 | **Smile** small → big → off; also laugh a bit | 1–2 min | Smile / cheeks |
| 5 | **Blink** a lot; hold eyes closed 2–3 s a few times | 1–2 min | Eye open / blink |
| 6 | Look **left**, then **right** (slow, then a bit faster) | 1–2 min | Head yaw |
| 7 | Look **up**, then **down** | 1–2 min | Head pitch |
| 8 | **Tilt / roll** head left and right (ear toward shoulder) | 1–2 min | Head roll |
| 9 | Combine: turn head **while talking** | 2–3 min | Real use case |
| 10 | **Raise eyebrows**, then lower; slight frown | 1–2 min | Brows |
| 11 | Move **closer** and **farther** once or twice | ~1 min | Scale / distance |
| 12 | Optional: **¾ side** view each side (not full back of head) | 1–2 min | Wider angles |
| 13 | Optional: **dimmer light** or side light (short second clip) | 2–5 min | Robustness if you stream dark |

**Rough total if you do the table once: ~20–30 minutes.**

### Good habits while filming

- Stay roughly centered; don’t leave the frame  
- Move smoothly, not only snap poses  
- Include **talking** — silent faces alone are not enough  
- Avoid covering your mouth with your hand for long stretches  
- Avoid only one expression for the whole video  

### Smoke test vs full train

In the Colab config cell:

```python
MAX_FRAMES = 2000   # smoke test (~subset of frames)
EPOCHS = 10
```

Full training after you have the full checklist video:

```python
MAX_FRAMES = 0      # use all labeled frames
EPOCHS = 40
```

---

## Dependencies

| Package | Pin | Notes |
|---------|-----|--------|
| OpenCV | `opencv-contrib-python>=5.0.0.93` | OpenCV 5; **contrib** package (MediaPipe expects it) |
| mediapipe | `>=0.10.35` | Teacher labels; [setup guide](https://developers.google.com/edge/mediapipe/solutions/setup_python) |
| onnx | `>=1.16` | Export |
| onnxruntime | `>=1.17` | Optional CPU check of exported model |
| torch | `>=2.1` | Training (Colab already provides a recent build) |

Install everything locally with:

```bash
pip install -r requirements.txt
```

**Important:** do not install `opencv-python-headless` in the same environment as MediaPipe. Both provide `cv2` and will conflict. Use **one** OpenCV wheel only (`opencv-contrib-python` here).

---

## Local training (optional)

```bash
pip install -r requirements.txt

python scripts/label_teacher.py --videos path/to/*.mp4 --out ./dataset
python scripts/train_student.py --data ./dataset --out ./runs/run1
python scripts/export_onnx.py \
  --ckpt ./runs/run1/best.pt \
  --out ./runs/run1/personal_face_student.onnx
```

Optional webcam check:

```bash
python scripts/infer_webcam.py --onnx ./runs/run1/personal_face_student.onnx
```

---

## After training

Keep these files from the run directory:

- `personal_face_student.onnx`
- `personal_face_student.json`
- `best.pt` (checkpoint, for re-export or more training)

Wire the ONNX into the OdinVTube runtime when ready (runtime integration is separate from this training folder).
