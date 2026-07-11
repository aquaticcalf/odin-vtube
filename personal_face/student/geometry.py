"""
Landmark → VTuber-style tracking params.
Used by the MediaPipe teacher to label YOUR video.
Indices follow MediaPipe Face Mesh (468 points).
"""

from __future__ import annotations

import math
from typing import Dict, List, Sequence, Tuple

import numpy as np

# MediaPipe Face Mesh indices (commonly used)
IDX_NOSE = 1
IDX_CHIN = 152
IDX_FOREHEAD = 10
IDX_LEFT_EYE_OUTER = 33
IDX_LEFT_EYE_INNER = 133
IDX_RIGHT_EYE_OUTER = 263
IDX_RIGHT_EYE_INNER = 362
IDX_LEFT_EYE_TOP = 159
IDX_LEFT_EYE_BOTTOM = 145
IDX_RIGHT_EYE_TOP = 386
IDX_RIGHT_EYE_BOTTOM = 374
IDX_MOUTH_LEFT = 61
IDX_MOUTH_RIGHT = 291
IDX_MOUTH_TOP = 13
IDX_MOUTH_BOTTOM = 14
IDX_LEFT_BROW = 105
IDX_RIGHT_BROW = 334


def _pt(lms: Sequence, i: int) -> np.ndarray:
    p = lms[i]
    if hasattr(p, "x"):
        return np.array([p.x, p.y, getattr(p, "z", 0.0)], dtype=np.float64)
    return np.array(p[:3], dtype=np.float64)


def eye_aspect_ratio(lms, top_i, bottom_i, outer_i, inner_i) -> float:
    t, b = _pt(lms, top_i), _pt(lms, bottom_i)
    o, inn = _pt(lms, outer_i), _pt(lms, inner_i)
    vert = np.linalg.norm(t[:2] - b[:2])
    hor = np.linalg.norm(o[:2] - inn[:2]) + 1e-6
    # open eyes ~0.25–0.35 ear; closed ~0.05–0.12 — map to 0..1
    ear = vert / hor
    open_amt = (ear - 0.08) / 0.22
    return float(np.clip(open_amt, 0.0, 1.0))


def mouth_open_amount(lms) -> float:
    top, bot = _pt(lms, IDX_MOUTH_TOP), _pt(lms, IDX_MOUTH_BOTTOM)
    left, right = _pt(lms, IDX_MOUTH_LEFT), _pt(lms, IDX_MOUTH_RIGHT)
    vert = np.linalg.norm(top[:2] - bot[:2])
    hor = np.linalg.norm(left[:2] - right[:2]) + 1e-6
    ratio = vert / hor
    return float(np.clip((ratio - 0.05) / 0.45, 0.0, 1.0))


def mouth_smile_amount(lms) -> float:
    """Rough smile: mouth corners relative to mouth center height."""
    left, right = _pt(lms, IDX_MOUTH_LEFT), _pt(lms, IDX_MOUTH_RIGHT)
    top, bot = _pt(lms, IDX_MOUTH_TOP), _pt(lms, IDX_MOUTH_BOTTOM)
    mid_y = 0.5 * (top[1] + bot[1])
    corner_y = 0.5 * (left[1] + right[1])
    # corners above mid → smile (image y grows downward)
    smile = (mid_y - corner_y) / 0.03
    return float(np.clip(smile, 0.0, 1.0))


def brow_height(lms, brow_i, eye_top_i) -> float:
    brow, eye = _pt(lms, brow_i), _pt(lms, eye_top_i)
    # larger gap → raised brow; normalize roughly
    gap = (eye[1] - brow[1])  # positive if brow above eye
    return float(np.clip(gap / 0.06, 0.0, 1.0))


def head_angles_deg(lms) -> Tuple[float, float, float]:
    """
    Approximate head pose in degrees from a few 3D mesh points.
    X = yaw (left/right), Y = pitch (up/down), Z = roll.
    Scale is VTS-ish: roughly ±30.
    """
    nose = _pt(lms, IDX_NOSE)
    chin = _pt(lms, IDX_CHIN)
    left_eye = _pt(lms, IDX_LEFT_EYE_OUTER)
    right_eye = _pt(lms, IDX_RIGHT_EYE_OUTER)
    forehead = _pt(lms, IDX_FOREHEAD)

    # Roll from eye line
    dy = right_eye[1] - left_eye[1]
    dx = right_eye[0] - left_eye[0] + 1e-6
    roll = math.degrees(math.atan2(dy, dx))
    # MediaPipe: subject left is +x often; flip for natural yaw
    mid_eye = 0.5 * (left_eye + right_eye)
    yaw = (nose[0] - mid_eye[0]) * 120.0  # scale heuristic
    # Pitch: nose vs midpoint eyes/chin
    face_h = abs(chin[1] - forehead[1]) + 1e-6
    pitch = ((mid_eye[1] - nose[1]) / face_h) * 40.0

    yaw = float(np.clip(yaw, -40, 40))
    pitch = float(np.clip(pitch, -30, 30))
    roll = float(np.clip(roll, -40, 40))
    return yaw, pitch, roll


def eye_gaze_approx(lms) -> Tuple[float, float]:
    """Very rough gaze from iris-ish center vs eye box (mesh has iris points on some versions)."""
    # Use eye center vs eye corners as weak proxy
    le_c = 0.5 * (_pt(lms, IDX_LEFT_EYE_OUTER) + _pt(lms, IDX_LEFT_EYE_INNER))
    re_c = 0.5 * (_pt(lms, IDX_RIGHT_EYE_OUTER) + _pt(lms, IDX_RIGHT_EYE_INNER))
    nose = _pt(lms, IDX_NOSE)
    # relative horizontal offset of eyes midpoint to nose
    mid = 0.5 * (le_c + re_c)
    gx = float(np.clip((mid[0] - nose[0]) * 8.0, -1, 1))
    gy = float(np.clip((nose[1] - mid[1]) * 8.0, -1, 1))
    return gx, gy


def landmarks_to_params(lms) -> Dict[str, float]:
    yaw, pitch, roll = head_angles_deg(lms)
    gx, gy = eye_gaze_approx(lms)
    return {
        "FaceAngleX": yaw,
        "FaceAngleY": pitch,
        "FaceAngleZ": roll,
        "EyeOpenLeft": eye_aspect_ratio(
            lms, IDX_LEFT_EYE_TOP, IDX_LEFT_EYE_BOTTOM, IDX_LEFT_EYE_OUTER, IDX_LEFT_EYE_INNER
        ),
        "EyeOpenRight": eye_aspect_ratio(
            lms, IDX_RIGHT_EYE_TOP, IDX_RIGHT_EYE_BOTTOM, IDX_RIGHT_EYE_OUTER, IDX_RIGHT_EYE_INNER
        ),
        "EyeRightX": gx,
        "EyeRightY": gy,
        "MouthOpen": mouth_open_amount(lms),
        "MouthSmile": mouth_smile_amount(lms),
        "BrowLeftY": brow_height(lms, IDX_LEFT_BROW, IDX_LEFT_EYE_TOP),
        "BrowRightY": brow_height(lms, IDX_RIGHT_BROW, IDX_RIGHT_EYE_TOP),
    }


def params_to_vector(params: Dict[str, float], names: List[str]) -> np.ndarray:
    return np.array([float(params[n]) for n in names], dtype=np.float32)


def face_bbox_from_landmarks(lms, pad: float = 0.25) -> Tuple[float, float, float, float]:
    """Normalized xyxy bbox 0..1 with padding."""
    xs, ys = [], []
    for i in range(min(len(lms), 468)):
        p = _pt(lms, i)
        xs.append(p[0])
        ys.append(p[1])
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    w, h = x1 - x0, y1 - y0
    x0 -= w * pad
    x1 += w * pad
    y0 -= h * pad
    y1 += h * pad
    return (
        float(np.clip(x0, 0, 1)),
        float(np.clip(y0, 0, 1)),
        float(np.clip(x1, 0, 1)),
        float(np.clip(y1, 0, 1)),
    )
