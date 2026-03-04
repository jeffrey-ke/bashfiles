---
name: visualize-se3-frames
description: Generate matplotlib code to visualize SE3 poses and coordinate frames in 3D. Use when the user needs to plot transformation matrices, coordinate frames, kinematic chains, or debug robot poses visually.
argument-hint: [optional: variable name or file containing poses]
---

# Visualize SE3 Frames

Plot SE3 poses (4x4 homogeneous transformation matrices) as RGB coordinate frame axes in a 3D matplotlib figure.

## Convention

- **RGB = XYZ**: Red = X-axis, Green = Y-axis, Blue = Z-axis
- SE3 matrix layout: rotation in `T[:3, :3]`, translation in `T[:3, 3]`
- Each column of the rotation matrix is a frame axis direction

## Core Recipe

```python
import numpy as np
import matplotlib.pyplot as plt

def plot_coordinate_frame(ax, T, label="", scale=0.01, alpha=0.8):
    """Plot an SE3 pose as RGB axes. T is a 4x4 homogeneous matrix."""
    origin = T[:3, 3]
    for i, color in enumerate(['red', 'green', 'blue']):
        axis = T[:3, i] * scale
        ax.quiver(origin[0], origin[1], origin[2],
                  axis[0], axis[1], axis[2],
                  color=color, alpha=alpha, arrow_length_ratio=0.1)
    if label:
        ax.text(origin[0], origin[1], origin[2], label, fontsize=8, alpha=0.7)

fig = plt.figure(figsize=(12, 8))
ax = fig.add_subplot(111, projection='3d')
```

## Adjusting Scale

The `scale` parameter controls arrow length relative to scene units:
- Meter-scale scenes: `scale=0.01` to `0.05`
- Millimeter-scale scenes: `scale=5` to `20`
- Normalized scenes: `scale=0.1` to `0.3`

## Drawing Kinematic Chains

Connect parent-child frames with black lines:

```python
for parent_pos, child_pos in connections:
    ax.plot([parent_pos[0], child_pos[0]],
            [parent_pos[1], child_pos[1]],
            [parent_pos[2], child_pos[2]],
            'k-', alpha=0.5, linewidth=1)
```

## Auto-fit Axis Limits

```python
all_positions = np.array([T[:3, 3] for T in all_transforms])
margin = 0.02  # adjust to scene scale
for setter, dim in [(ax.set_xlim, 0), (ax.set_ylim, 1), (ax.set_zlim, 2)]:
    setter(all_positions[:, dim].min() - margin, all_positions[:, dim].max() + margin)
```

## Custom Legend

```python
from matplotlib.lines import Line2D
ax.legend(handles=[
    Line2D([0], [0], color='red', lw=2, label='X-axis'),
    Line2D([0], [0], color='green', lw=2, label='Y-axis'),
    Line2D([0], [0], color='blue', lw=2, label='Z-axis'),
], loc='upper right')
```

## Chaining Transforms

To accumulate transformations along a kinematic chain:

```python
T_cumulative = np.eye(4)
for T_joint in joint_transforms:
    T_cumulative = T_cumulative @ T_joint
    plot_coordinate_frame(ax, T_cumulative, ...)
```

## When Applying This Skill

1. Determine the scene scale (meters vs mm) and set `scale` accordingly
2. Plot the world/root frame at identity `np.eye(4)` as a reference
3. Plot each SE3 pose with a descriptive label
4. If poses form a chain, draw connecting lines between origins
5. Auto-fit axis limits so nothing is clipped
6. Add the RGB legend so the viewer knows which axis is which
