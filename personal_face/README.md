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

### Recording tips

- About **15–40 minutes** total is a good start  
- Talk, smile, blink, look around, tilt your head, raise brows  
- Use your normal desk lighting and camera distance  
- MP4 (H.264), 720p or 1080p at 30 fps is fine  

For a quick smoke test in the notebook config cell:

```python
MAX_FRAMES = 2000
EPOCHS = 10
```

Full run: `MAX_FRAMES = 0`, `EPOCHS = 40`.

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
