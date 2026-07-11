"""Tiny student network: face crop -> tracking params (you-only distillation)."""

from __future__ import annotations

import torch
import torch.nn as nn

# Param order written by the teacher and expected at inference.
PARAM_NAMES = [
    "FaceAngleX",
    "FaceAngleY",
    "FaceAngleZ",
    "EyeOpenLeft",
    "EyeOpenRight",
    "EyeRightX",
    "EyeRightY",
    "MouthOpen",
    "MouthSmile",
    "BrowLeftY",
    "BrowRightY",
]

NUM_PARAMS = len(PARAM_NAMES)  # 11


class TinyFaceStudent(nn.Module):
    """
    Very small CNN for single-person VTuber tracking.
    Input:  RGB float tensor [B, 3, H, W] in 0..1  (default H=W=128)
    Output: [B, NUM_PARAMS] raw values (same scale as teacher labels)
    """

    def __init__(self, img_size: int = 128, num_params: int = NUM_PARAMS):
        super().__init__()
        self.img_size = img_size
        self.num_params = num_params

        # ~0.3–0.5M params depending on channels — fine for low RAM inference
        self.backbone = nn.Sequential(
            nn.Conv2d(3, 16, 3, stride=2, padding=1),  # 64
            nn.BatchNorm2d(16),
            nn.ReLU(inplace=True),
            nn.Conv2d(16, 32, 3, stride=2, padding=1),  # 32
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.Conv2d(32, 64, 3, stride=2, padding=1),  # 16
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, 96, 3, stride=2, padding=1),  # 8
            nn.BatchNorm2d(96),
            nn.ReLU(inplace=True),
            nn.Conv2d(96, 128, 3, stride=2, padding=1),  # 4
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool2d(1),
        )
        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(128, 64),
            nn.ReLU(inplace=True),
            nn.Dropout(0.1),
            nn.Linear(64, num_params),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.head(self.backbone(x))


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters() if p.requires_grad)
