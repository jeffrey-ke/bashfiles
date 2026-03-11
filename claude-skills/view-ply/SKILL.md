---
name: view-ply
description: View a binary PLY pointcloud file with per-vertex RGB colors in a 3D matplotlib plot. Use when the user has a .ply file and wants to visualize it interactively. Standalone — no project dependencies beyond numpy and matplotlib.
argument-hint: <path-to-ply-file> [--subsample N] [--point-size S]
---

# View PLY Pointcloud

Standalone viewer for binary PLY files with per-vertex RGB colors (x, y, z, red, green, blue layout).

## Usage

```bash
python3 view_ply.py cloud.ply
python3 view_ply.py cloud.ply --subsample 4 --point-size 0.1
```

## Script

```python
"""View a binary PLY pointcloud file. Standalone — no project dependencies."""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


PLY_DTYPE = np.dtype([
    ("x", "<f4"), ("y", "<f4"), ("z", "<f4"),
    ("red", "u1"), ("green", "u1"), ("blue", "u1"),
])


def load_ply(path):
    with open(path, "rb") as f:
        line = f.readline()
        if line.strip() != b"ply":
            raise ValueError("Not a PLY file")
        n_vertices = None
        while True:
            line = f.readline().decode("ascii").strip()
            if line.startswith("element vertex"):
                n_vertices = int(line.split()[-1])
            if line == "end_header":
                break
        if n_vertices is None:
            raise ValueError("No vertex count in PLY header")
        return np.frombuffer(f.read(n_vertices * PLY_DTYPE.itemsize), dtype=PLY_DTYPE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--point-size", type=float, default=0.05)
    parser.add_argument("--subsample", type=int, default=None,
                        help="plot every Nth point (speeds up rendering)")
    args = parser.parse_args()

    pts = load_ply(args.path)
    if args.subsample:
        pts = pts[::args.subsample]
    print(f"{len(pts)} points")

    rgb = np.column_stack([pts["red"], pts["green"], pts["blue"]]) / 255.0

    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_subplot(projection="3d")

    ax.scatter(
        pts["x"], pts["y"], pts["z"],
        c=rgb, s=args.point_size, rasterized=True,
    )

    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.set_zlabel("z (m)")
    ax.set_title(f"{args.path.name} ({len(pts)} points)")
    plt.show()


if __name__ == "__main__":
    main()
```

## Workflow: Remote Accumulate → Local View

On the remote machine, generate the PLY:

```bash
python3 -m pointclean.plot_accumulated path/to/data.mcap --ply cloud.ply -n 10
```

rsync locally:

```bash
rsync remote:path/to/cloud.ply .
```

View locally:

```bash
python3 view_ply.py cloud.ply
```

## Notes

- The PLY files use binary little-endian format with the dtype above (15 bytes/point)
- Colors are baked in at save time from the intensity colormap — the viewer just displays RGB
- Use `--subsample 4` or higher if matplotlib is sluggish with large clouds
- For best performance with very large clouds, open the PLY in MeshLab or CloudCompare instead
