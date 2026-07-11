#!/usr/bin/env python3
"""
Teacher labeling: YOUR video(s) -> MediaPipe Face Mesh -> crops + param vectors.

Output dataset layout:
  out_dir/
    meta.json
    samples.npz   # images uint8 [N,H,W,3], params float32 [N,P], optional paths
    preview/      # a few debug jpgs

Usage (Colab or local):
  python label_teacher.py --videos /content/drive/MyDrive/myface/*.mp4 --out /content/drive/MyDrive/odin_face_data
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path

import cv2
import numpy as np
from tqdm import tqdm

# allow running from repo root or scripts/
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from student.geometry import (  # noqa: E402
    face_bbox_from_landmarks,
    landmarks_to_params,
    params_to_vector,
)
from student.model import PARAM_NAMES  # noqa: E402


def parse_args():
    p = argparse.ArgumentParser(description="Label personal face videos with MediaPipe teacher")
    p.add_argument(
        "--videos",
        nargs="+",
        required=True,
        help="Video paths or globs (quote globs on Windows)",
    )
    p.add_argument("--out", type=str, required=True, help="Output dataset directory")
    p.add_argument("--img-size", type=int, default=128)
    p.add_argument("--every-n", type=int, default=2, help="Keep every Nth frame")
    p.add_argument("--max-frames", type=int, default=0, help="0 = no limit (per all videos)")
    p.add_argument("--min-confidence", type=float, default=0.5)
    p.add_argument("--preview-every", type=int, default=200)
    return p.parse_args()


def expand_videos(patterns):
    paths = []
    for pat in patterns:
        matched = sorted(glob.glob(pat))
        if matched:
            paths.extend(matched)
        elif os.path.isfile(pat):
            paths.append(pat)
        else:
            print(f"[warn] no match: {pat}")
    # unique preserve order
    seen = set()
    out = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def crop_face(frame_bgr, bbox_norm, img_size: int):
    h, w = frame_bgr.shape[:2]
    x0, y0, x1, y1 = bbox_norm
    x0i, y0i = int(x0 * w), int(y0 * h)
    x1i, y1i = int(x1 * w), int(y1 * h)
    x0i, y0i = max(0, x0i), max(0, y0i)
    x1i, y1i = min(w, x1i), min(h, y1i)
    if x1i - x0i < 8 or y1i - y0i < 8:
        return None
    crop = frame_bgr[y0i:y1i, x0i:x1i]
    crop = cv2.resize(crop, (img_size, img_size), interpolation=cv2.INTER_AREA)
    crop = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
    return crop


def main():
    args = parse_args()
    videos = expand_videos(args.videos)
    if not videos:
        print("No videos found.")
        sys.exit(1)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    preview_dir = out_dir / "preview"
    preview_dir.mkdir(exist_ok=True)

    import mediapipe as mp

    mp_face = mp.solutions.face_mesh
    mesh = mp_face.FaceMesh(
        static_image_mode=False,
        max_num_faces=1,
        refine_landmarks=True,
        min_detection_confidence=args.min_confidence,
        min_tracking_confidence=args.min_confidence,
    )

    images = []
    params_list = []
    total_seen = 0
    total_kept = 0

    try:
        for vpath in videos:
            print(f"[video] {vpath}")
            cap = cv2.VideoCapture(vpath)
            if not cap.isOpened():
                print(f"  failed to open")
                continue
            frame_i = 0
            pbar = tqdm(desc=Path(vpath).name, unit="f")
            while True:
                ok, frame = cap.read()
                if not ok:
                    break
                total_seen += 1
                pbar.update(1)
                if frame_i % args.every_n != 0:
                    frame_i += 1
                    continue
                frame_i += 1

                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                res = mesh.process(rgb)
                if not res.multi_face_landmarks:
                    continue
                lms = res.multi_face_landmarks[0].landmark
                try:
                    pdict = landmarks_to_params(lms)
                    vec = params_to_vector(pdict, PARAM_NAMES)
                    bbox = face_bbox_from_landmarks(lms, pad=0.28)
                    crop = crop_face(frame, bbox, args.img_size)
                except Exception as e:
                    print(f"  skip frame err: {e}")
                    continue
                if crop is None:
                    continue

                images.append(crop)
                params_list.append(vec)
                total_kept += 1

                if args.preview_every > 0 and total_kept % args.preview_every == 1:
                    prev = cv2.cvtColor(crop, cv2.COLOR_RGB2BGR)
                    label = f"m={vec[7]:.2f} s={vec[8]:.2f} yaw={vec[0]:.1f}"
                    cv2.putText(
                        prev, label, (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1
                    )
                    cv2.imwrite(str(preview_dir / f"sample_{total_kept:06d}.jpg"), prev)

                if args.max_frames > 0 and total_kept >= args.max_frames:
                    break
            pbar.close()
            cap.release()
            if args.max_frames > 0 and total_kept >= args.max_frames:
                break
    finally:
        mesh.close()

    if total_kept == 0:
        print("No labeled frames. Check video has a clear face.")
        sys.exit(2)

    images_np = np.stack(images, axis=0).astype(np.uint8)
    params_np = np.stack(params_list, axis=0).astype(np.float32)

    # shuffle
    rng = np.random.default_rng(42)
    idx = rng.permutation(len(images_np))
    images_np = images_np[idx]
    params_np = params_np[idx]

    # train/val split
    n = len(images_np)
    n_val = max(1, int(n * 0.1))
    split = {
        "train": int(n - n_val),
        "val": int(n_val),
    }

    np.savez_compressed(
        out_dir / "samples.npz",
        images=images_np,
        params=params_np,
        param_names=np.array(PARAM_NAMES),
    )

    meta = {
        "num_samples": n,
        "img_size": args.img_size,
        "param_names": PARAM_NAMES,
        "videos": videos,
        "every_n": args.every_n,
        "frames_seen": total_seen,
        "split": split,
        "teacher": "mediapipe_face_mesh",
        "notes": "Personal distillation dataset — single subject expected",
    }
    with open(out_dir / "meta.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    print(f"[done] kept {total_kept} / seen {total_seen}")
    print(f"[done] wrote {out_dir / 'samples.npz'}")
    print(f"[done] previews in {preview_dir}")


if __name__ == "__main__":
    main()
