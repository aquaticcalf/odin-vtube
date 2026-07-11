#!/usr/bin/env python3
"""
Export best.pt -> personal_face_student.onnx

  python export_onnx.py --ckpt /content/drive/MyDrive/odin_face_runs/run1/best.pt --out /content/drive/MyDrive/odin_face_runs/run1/personal_face_student.onnx
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from student.model import PARAM_NAMES, TinyFaceStudent  # noqa: E402


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", type=str, required=True)
    p.add_argument("--out", type=str, required=True)
    p.add_argument("--opset", type=int, default=17)
    return p.parse_args()


def main():
    args = parse_args()
    ckpt_path = Path(args.ckpt)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    img_size = int(ckpt.get("img_size", 128))
    names = ckpt.get("param_names", PARAM_NAMES)

    model = TinyFaceStudent(img_size=img_size)
    model.load_state_dict(ckpt["model"])
    model.eval()

    dummy = torch.randn(1, 3, img_size, img_size)
    torch.onnx.export(
        model,
        dummy,
        str(out_path),
        input_names=["face_rgb"],
        output_names=["params"],
        dynamic_axes={"face_rgb": {0: "batch"}, "params": {0: "batch"}},
        opset_version=args.opset,
        do_constant_folding=True,
    )

    # sidecar for Odin / inference
    meta = {
        "onnx": out_path.name,
        "img_size": img_size,
        "param_names": list(names),
        "input": "face_rgb [N,3,H,W] float32 0..1 RGB",
        "output": "params [N,P] float32",
        "val_loss": ckpt.get("val_loss"),
        "epoch": ckpt.get("epoch"),
    }
    with open(out_path.with_suffix(".json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    size_mb = out_path.stat().st_size / (1024 * 1024)
    print(f"[done] {out_path}  ({size_mb:.2f} MB)")
    print(f"[done] {out_path.with_suffix('.json')}")

    # quick ORT check if available
    try:
        import numpy as np
        import onnxruntime as ort

        sess = ort.InferenceSession(str(out_path), providers=["CPUExecutionProvider"])
        inp = np.random.rand(1, 3, img_size, img_size).astype(np.float32)
        out = sess.run(None, {"face_rgb": inp})[0]
        print(f"[ort] ok output shape={out.shape}")
    except Exception as e:
        print(f"[ort] skip check: {e}")


if __name__ == "__main__":
    main()
