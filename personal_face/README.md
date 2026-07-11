# Personal Face Student (you-only, low RAM)

Distill **MediaPipe teacher** labels from **your** webcam videos into a **tiny CNN** → **ONNX** for OdinVTube.

```
Your MP4s  →  label_teacher.py  →  samples.npz
                                    ↓
                            train_student.py
                                    ↓
                            export_onnx.py  →  personal_face_student.onnx
```

## Layout

```
personal_face/
  student/
    model.py       # TinyFaceStudent (~small)
    geometry.py    # landmarks → FaceAngle / mouth / eyes
  scripts/
    label_teacher.py
    train_student.py
    export_onnx.py
    infer_webcam.py
  notebooks/
    Personal_Face_Train_Colab.ipynb
  requirements.txt
```

## Output params (11)

`FaceAngleX/Y/Z`, `EyeOpenLeft/Right`, `EyeRightX/Y`, `MouthOpen`, `MouthSmile`, `BrowLeftY/RightY`

## Colab (recommended)

Repo is expected at: **https://github.com/aquaticcalf/odin-vtube**

1. Upload face videos to `Google Drive/odin_face/videos/*.mp4`
2. Open `personal_face/notebooks/Personal_Face_Train_Colab.ipynb` in Colab  
   (or File → Open notebook from GitHub: `aquaticcalf/odin-vtube`)
3. **Runtime → GPU**
4. Run all cells — notebook clones the repo automatically

## Local (optional)

```bash
pip install -r requirements.txt
python scripts/label_teacher.py --videos path/to/*.mp4 --out ./dataset
python scripts/train_student.py --data ./dataset --out ./runs/run1
python scripts/export_onnx.py --ckpt ./runs/run1/best.pt --out ./runs/run1/personal_face_student.onnx
```

## Tips

- 15–40 min of **you** doing faces is enough to start
- Smoke test: `--max-frames 2000` when labeling
- Full run: `MAX_FRAMES = 0`, `EPOCHS = 40`
- Model is meant to overfit **you** — that is intentional
