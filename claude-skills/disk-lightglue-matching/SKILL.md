---
name: disk-lightglue-matching
description: Drop-in DISK + LightGlue learned feature matching pipeline using kornia. Use when the user wants learned feature matching instead of classical (SIFT/ORB).
argument-hint: <none>
---

# DISK + LightGlue Feature Matching (kornia 0.8.x)

Learned feature detection (DISK) and matching (LightGlue) via kornia. Dramatically better than classical matchers on viewpoint changes.

## Prerequisites

```bash
pip install kornia kornia-rs
```

SuperPoint extractor is **not** in kornia 0.8.x. Use DISK as the feature backbone — same quality tier.

## Core Recipe

```python
import cv2
import numpy as np
import torch
import kornia
import kornia.feature as KF

_DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
_DISK = KF.DISK.from_pretrained('depth').eval().to(_DEVICE)
_LIGHTGLUE = KF.LightGlueMatcher('disk').eval().to(_DEVICE)

def _to_rgb_tensor(bgr: np.ndarray) -> torch.Tensor:
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB) if bgr.ndim == 3 and bgr.shape[2] >= 3 else bgr
    return kornia.image_to_tensor(rgb).float().div(255.0).unsqueeze(0).to(_DEVICE)

def detect(image: np.ndarray, n: int = 2048) -> KF.DISKFeatures:
    t = _to_rgb_tensor(image)
    with torch.inference_mode():
        return _DISK(t, n, pad_if_not_divisible=True)[0]

def lightglue_match(feats1: KF.DISKFeatures, feats2: KF.DISKFeatures,
                    hw1: tuple[int, int], hw2: tuple[int, int]) -> torch.Tensor:
    lafs1 = KF.laf_from_center_scale_ori(feats1.keypoints[None], torch.ones(1, feats1.n, 1, 1, device=_DEVICE))
    lafs2 = KF.laf_from_center_scale_ori(feats2.keypoints[None], torch.ones(1, feats2.n, 1, 1, device=_DEVICE))
    with torch.inference_mode():
        _, idxs = _LIGHTGLUE(feats1.descriptors, feats2.descriptors, lafs1, lafs2,
                              hw1=hw1, hw2=hw2)
    return idxs

def match(left_image: np.ndarray, right_image: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    feats_left = detect(left_image)
    feats_right = detect(right_image)
    idxs = lightglue_match(feats_left, feats_right,
                           hw1=left_image.shape[:2], hw2=right_image.shape[:2])
    pts_left = feats_left.keypoints[idxs[:, 0]].cpu().numpy()
    pts_right = feats_right.keypoints[idxs[:, 1]].cpu().numpy()
    return pts_left, pts_right
```

## API Notes

- `KF.DISK.from_pretrained('depth')` downloads weights on first call (~4 MB).
- `KF.LightGlueMatcher('disk')` downloads LightGlue weights (~45 MB).
- Pass `hw1`/`hw2` as plain tuples `(H, W)` — kornia converts internally. Passing `torch.tensor(...)` triggers a double-wrap warning.
- `lightglue_match` returns `(N, 2)` index tensor: column 0 indexes into `feats1`, column 1 into `feats2`.
- `DISKFeatures` fields: `.keypoints` (N, 2), `.descriptors` (N, 128), `.detection_scores` (N,), `.n` property.
- `laf_from_center_scale_ori` wants shape `(1, N, 2, 3)` for LAFs and `(1, N, 1, 1)` for scale.

## When Applying This Skill

1. Ensure kornia >= 0.8.0 is installed.
2. Module-level `_DISK` and `_LIGHTGLUE` are loaded once at import time (GPU memory cost).
3. `detect` and `lightglue_match` are independently callable — detect once, match many.
4. Input images are BGR (OpenCV convention). The `_to_rgb_tensor` helper handles conversion.
