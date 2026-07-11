#!/usr/bin/env python3
"""
Quick local test of exported ONNX with webcam (optional).
Uses MediaPipe only for face crop bbox; params come from YOUR student.

  python infer_webcam.py --onnx path/to/personal_face_student.onnx
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from student.geometry import face_bbox_from_landmarks  # noqa: E402
from student.model import PARAM_NAMES  # noqa: E402


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--onnx", type=str, required=True)
    p.add_argument("--meta", type=str, default="", help="optional .json next to onnx")
    p.add_argument("--camera", type=int, default=0)
    return p.parse_args()


def main():
    args = parse_args()
    import onnxruntime as ort
    import mediapipe as mp

    meta_path = Path(args.meta) if args.meta else Path(args.onnx).with_suffix(".json")
    img_size = 128
    names = PARAM_NAMES
    if meta_path.is_file():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        img_size = int(meta.get("img_size", 128))
        names = list(meta.get("param_names", PARAM_NAMES))

    sess = ort.InferenceSession(args.onnx, providers=["CPUExecutionProvider"])
    mesh = mp.solutions.face_mesh.FaceMesh(
        max_num_faces=1, refine_landmarks=True, min_detection_confidence=0.5
    )

    cap = cv2.VideoCapture(args.camera)
    print("Press Q to quit")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        h, w = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        res = mesh.process(rgb)
        text = "no face"
        if res.multi_face_landmarks:
            lms = res.multi_face_landmarks[0].landmark
            x0, y0, x1, y1 = face_bbox_from_landmarks(lms, pad=0.28)
            x0i, y0i = int(x0 * w), int(y0 * h)
            x1i, y1i = int(x1 * w), int(y1 * h)
            crop = frame[y0i:y1i, x0i:x1i]
            if crop.size > 0:
                crop = cv2.resize(crop, (img_size, img_size))
                crop = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
                inp = crop.transpose(2, 0, 1)[None, ...]
                out = sess.run(None, {"face_rgb": inp})[0][0]
                text = " ".join(f"{n[:4]}={v:.1f}" for n, v in zip(names[:4], out[:4]))
                text2 = f"mouth={out[7]:.2f} smile={out[8]:.2f}"
                cv2.rectangle(frame, (x0i, y0i), (x1i, y1i), (0, 255, 0), 2)
                cv2.putText(frame, text, (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 0), 2)
                cv2.putText(frame, text2, (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 0), 2)
        else:
            cv2.putText(frame, text, (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)

        cv2.imshow("personal student", frame)
        if cv2.waitKey(1) & 0xFF in (ord("q"), ord("Q")):
            break

    cap.release()
    cv2.destroyAllWindows()
    mesh.close()


if __name__ == "__main__":
    main()
