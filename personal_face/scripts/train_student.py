#!/usr/bin/env python3
"""
Train TinyFaceStudent on teacher-labeled personal dataset.

  python train_student.py --data /content/drive/MyDrive/odin_face_data --out /content/drive/MyDrive/odin_face_runs/run1
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
from tqdm import tqdm

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from student.model import PARAM_NAMES, TinyFaceStudent, count_parameters  # noqa: E402


class FaceParamDataset(Dataset):
    def __init__(self, images: np.ndarray, params: np.ndarray, augment: bool = False):
        self.images = images
        self.params = params
        self.augment = augment

    def __len__(self):
        return len(self.images)

    def __getitem__(self, i):
        img = self.images[i].astype(np.float32) / 255.0  # HWC RGB
        y = self.params[i].astype(np.float32).copy()

        if self.augment:
            # horizontal flip + swap L/R params
            if np.random.rand() < 0.5:
                img = img[:, ::-1, :].copy()
                # FaceAngleX, FaceAngleZ flip sign; swap eyes/brows
                y[0] = -y[0]  # yaw
                y[2] = -y[2]  # roll
                y[3], y[4] = y[4], y[3]  # eye open L/R
                y[5] = -y[5]  # gaze x
                y[9], y[10] = y[10], y[9]  # brows
            # mild brightness
            if np.random.rand() < 0.5:
                img = np.clip(img * np.random.uniform(0.85, 1.15), 0, 1)

        # HWC -> CHW
        x = torch.from_numpy(img.transpose(2, 0, 1))
        y = torch.from_numpy(y)
        return x, y


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--data", type=str, required=True, help="Dataset dir with samples.npz")
    p.add_argument("--out", type=str, required=True, help="Run output directory")
    p.add_argument("--epochs", type=int, default=40)
    p.add_argument("--batch", type=int, default=64)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--img-size", type=int, default=128)
    p.add_argument("--workers", type=int, default=2)
    p.add_argument("--seed", type=int, default=42)
    return p.parse_args()


def main():
    args = parse_args()
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    data_dir = Path(args.data)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    npz = np.load(data_dir / "samples.npz", allow_pickle=True)
    images = npz["images"]
    params = npz["params"]
    names = list(npz["param_names"]) if "param_names" in npz else PARAM_NAMES
    assert list(names) == list(PARAM_NAMES), f"param names mismatch: {names}"

    n = len(images)
    n_val = max(1, int(n * 0.1))
    n_train = n - n_val
    # already shuffled at label time; take tail as val
    train_ds = FaceParamDataset(images[:n_train], params[:n_train], augment=True)
    val_ds = FaceParamDataset(images[n_train:], params[n_train:], augment=False)

    train_loader = DataLoader(
        train_ds, batch_size=args.batch, shuffle=True, num_workers=args.workers, drop_last=False
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch, shuffle=False, num_workers=args.workers
    )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = TinyFaceStudent(img_size=args.img_size).to(device)
    print(f"[model] params={count_parameters(model):,} device={device}")

    # Per-param weights: angles matter, mouth/eyes matter more than gaze noise
    w = torch.tensor(
        [1.0, 1.0, 1.0, 1.2, 1.2, 0.5, 0.5, 1.5, 1.2, 0.8, 0.8],
        device=device,
        dtype=torch.float32,
    )

    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)
    loss_fn = nn.SmoothL1Loss(reduction="none")

    best_val = float("inf")
    history = []

    for epoch in range(1, args.epochs + 1):
        model.train()
        tr_loss = 0.0
        n_tr = 0
        for x, y in tqdm(train_loader, desc=f"epoch {epoch}/{args.epochs} train", leave=False):
            x, y = x.to(device), y.to(device)
            pred = model(x)
            per = loss_fn(pred, y)  # [B,P]
            loss = (per * w).mean()
            opt.zero_grad()
            loss.backward()
            opt.step()
            tr_loss += loss.item() * x.size(0)
            n_tr += x.size(0)
        sched.step()
        tr_loss /= max(1, n_tr)

        model.eval()
        va_loss = 0.0
        n_va = 0
        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                pred = model(x)
                per = loss_fn(pred, y)
                loss = (per * w).mean()
                va_loss += loss.item() * x.size(0)
                n_va += x.size(0)
        va_loss /= max(1, n_va)

        history.append({"epoch": epoch, "train": tr_loss, "val": va_loss})
        print(f"epoch {epoch:03d}  train={tr_loss:.5f}  val={va_loss:.5f}")

        ckpt = {
            "model": model.state_dict(),
            "param_names": PARAM_NAMES,
            "img_size": args.img_size,
            "epoch": epoch,
            "val_loss": va_loss,
        }
        torch.save(ckpt, out_dir / "last.pt")
        if va_loss < best_val:
            best_val = va_loss
            torch.save(ckpt, out_dir / "best.pt")
            print(f"  -> saved best.pt (val={best_val:.5f})")

    with open(out_dir / "history.json", "w", encoding="utf-8") as f:
        json.dump(history, f, indent=2)

    meta = {
        "best_val": best_val,
        "epochs": args.epochs,
        "num_train": n_train,
        "num_val": n_val,
        "param_names": PARAM_NAMES,
        "img_size": args.img_size,
        "num_parameters": count_parameters(model),
        "finished_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    with open(out_dir / "run_meta.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    print(f"[done] best_val={best_val:.5f}")
    print(f"[done] {out_dir / 'best.pt'}")


if __name__ == "__main__":
    main()
