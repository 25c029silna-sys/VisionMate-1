import cv2
import numpy as np
import sys
import re
from scipy.spatial import cKDTree
from scipy.signal import find_peaks

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')
from braille_ocr.dot_segmenter import (
    EmbossedDot,
    BrailleGridCell,
    estimate_global_pitches,
    grid_coords_to_dot_index
)
from braille_ocr.grade2_decoder import LiblouisGrade2Decoder

def run_pipeline(img_path='ml/yolov8_braille/captured_phone_2.jpg'):
    img = cv2.imread(img_path)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape

    # 1. Adaptive Dot Detection for Embossed Paper
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    smoothed = cv2.GaussianBlur(enhanced, (5, 5), 1.0)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
    tophat = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)
    blackhat = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)

    tiles_y = max(2, h // 160)
    tiles_x = max(2, w // 160)
    bin_crest = np.zeros_like(tophat)
    bin_trough = np.zeros_like(blackhat)
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            y1, y2 = ty * h // tiles_y, (ty + 1) * h // tiles_y
            x1, x2 = tx * w // tiles_x, (tx + 1) * w // tiles_x
            t_th = tophat[y1:y2, x1:x2]
            t_bh = blackhat[y1:y2, x1:x2]
            local_top_thresh = max(7.0, float(np.mean(t_th) + 0.95 * np.std(t_th)))
            local_black_thresh = max(7.0, float(np.mean(t_bh) + 0.95 * np.std(t_bh)))
            bin_crest[y1:y2, x1:x2] = (t_th >= local_top_thresh).astype(np.uint8) * 255
            bin_trough[y1:y2, x1:x2] = (t_bh >= local_black_thresh).astype(np.uint8) * 255

    num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
    num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)

    crests = []
    for i in range(1, num_c):
        area = stats_c[i, cv2.CC_STAT_AREA]
        if 10 <= area <= 350:
            bw = stats_c[i, cv2.CC_STAT_WIDTH]
            bh_c = stats_c[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh_c) if bh_c > 0 else 0
            if 0.55 <= aspect <= 1.80:
                cx_c, cy_c = cent_c[i][0], cent_c[i][1]
                val = float(tophat[int(cy_c), int(cx_c)])
                crests.append((cx_c, cy_c, float(area), val))

    troughs = []
    for i in range(1, num_t):
        area = stats_t[i, cv2.CC_STAT_AREA]
        if 10 <= area <= 350:
            bw = stats_t[i, cv2.CC_STAT_WIDTH]
            bh_t = stats_t[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh_t) if bh_t > 0 else 0
            if 0.55 <= aspect <= 1.80:
                cx_t, cy_t = cent_t[i][0], cent_t[i][1]
                val = float(blackhat[int(cy_t), int(cx_t)])
                troughs.append((cx_t, cy_t, float(area), val))

    dots = []
    if crests and troughs:
        troughs_arr = np.array([[t[0], t[1]] for t in troughs], dtype=np.float32)
        crests_arr = np.array([[c[0], c[1]] for c in crests], dtype=np.float32)
        trough_tree = cKDTree(troughs_arr)
        dists, min_indices = trough_tree.query(crests_arr, k=1)
        for i, d in enumerate(dists):
            if 2.0 <= d <= 20.0:
                c_x, c_y, _, c_val = crests[i]
                min_idx = min_indices[i]
                t_x, t_y, _, t_val = troughs[min_idx]
                total_contrast = c_val + t_val
                if total_contrast >= 14.0:
                    dot_x = 0.7 * c_x + 0.3 * t_x
                    dot_y = 0.7 * c_y + 0.3 * t_y
                    dots.append(EmbossedDot(x=dot_x, y=dot_y, radius=float(d/2.0), contrast=total_contrast, vector_dx=t_x-c_x, vector_dy=t_y-c_y))

    # Fast spatial hash NMS
    dots.sort(key=lambda d: d.contrast, reverse=True)
    grid_nms = {}
    kept_dots = []
    for d in dots:
        gx, gy = int(d.x // 5.0), int(d.y // 5.0)
        if any((gx + ox, gy + oy) in grid_nms for ox in (-1, 0, 1) for oy in (-1, 0, 1)):
            continue
        grid_nms[(gx, gy)] = d
        kept_dots.append(d)

    print(f"Adaptive dots detected: {len(kept_dots)}")

    # 2. Pitches
    dx, dy, cx = estimate_global_pitches(kept_dots)
    print(f"Pitches: dx={dx:.1f}, dy={dy:.1f}, cx={cx:.1f}")

    # Estimate page line skew angle from neighbor dot pairs
    pts = np.array([[d.x, d.y] for d in kept_dots], dtype=np.float32)
    tree_dots = cKDTree(pts)
    angles = []
    for p in pts:
        idxs = tree_dots.query_ball_point(p, r=cx * 1.2)
        for j in idxs:
            diff = pts[j] - p
            if (dx * 0.7) <= diff[0] <= (cx * 1.5) and abs(diff[1]) <= (dy * 0.6):
                ang = np.degrees(np.arctan2(diff[1], diff[0]))
                angles.append(ang)

    skew_angle = float(np.median(angles)) if angles else 0.0
    print(f"Estimated line skew angle: {skew_angle:.3f} deg")

    # Rotate dots to horizontal alignment
    theta = np.radians(skew_angle)
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    cx_img, cy_img = w / 2.0, h / 2.0

    # (x, y) rotated
    x_rot = cos_t * (pts[:, 0] - cx_img) + sin_t * (pts[:, 1] - cy_img) + cx_img
    y_rot = -sin_t * (pts[:, 0] - cx_img) + cos_t * (pts[:, 1] - cy_img) + cy_img
    pts_rot = np.column_stack([x_rot, y_rot])

    # 3. Y-projection KDE for line baselines
    y_min, y_max = float(y_rot.min()), float(y_rot.max())
    y_grid = np.arange(y_min - dy, y_max + dy, 1.0, dtype=np.float32)
    density = np.zeros_like(y_grid)
    sigma = max(4.0, dy * 0.70)
    for y in y_rot:
        density += np.exp(-0.5 * ((y_grid - y) / sigma)**2)

    min_dist = max(int(round(dy * 2.8)), 15)
    peaks, _ = find_peaks(density, distance=min_dist, height=float(np.mean(density) * 0.20))
    raw_lines = sorted([float(y_grid[p]) for p in peaks])

    # Interpolate missing lines based on median line pitch
    diffs = np.diff(raw_lines)
    valid_diffs = diffs[(diffs >= dy * 2.5) & (diffs <= dy * 8.0)]
    med_lh = float(np.median(valid_diffs)) if len(valid_diffs) > 0 else (dy * 4.5)
    print(f"Raw lines: {len(raw_lines)}, Median LH: {med_lh:.1f}")

    interpolated_lines = [raw_lines[0]]
    for i in range(len(raw_lines) - 1):
        y_curr = raw_lines[i]
        y_next = raw_lines[i + 1]
        gap = y_next - y_curr
        num_missing = int(round(gap / med_lh)) - 1
        if num_missing >= 1:
            step_lh = gap / (num_missing + 1)
            for m in range(1, num_missing + 1):
                interpolated_lines.append(y_curr + m * step_lh)
        interpolated_lines.append(y_next)
    interpolated_lines.sort()

    print(f"Interpolated lines: {len(interpolated_lines)}")

    # 4. Continuous 2x3 Grid Lattice Projection
    rot_tree = cKDTree(pts_rot)
    decoder = LiblouisGrade2Decoder()

    # Diagnostics canvas
    debug_canvas = img.copy()
    for d in kept_dots:
        cv2.circle(debug_canvas, (int(round(d.x)), int(round(d.y))), 3, (0, 255, 0), -1)

    node_tol = dx * 0.46
    ambiguous_tol = dx * 0.62

    all_decoded_lines = []

    for line_idx, line_y in enumerate(interpolated_lines):
        m_line = np.abs(pts_rot[:, 1] - line_y) <= (dy * 1.5)
        pts_in_line = pts_rot[m_line]
        if len(pts_in_line) < 3:
            continue
        xs = pts_in_line[:, 0]
        ys = pts_in_line[:, 1]

        # Fit vertical Row 0 Y0
        cand_y0s = np.linspace(line_y - dy, line_y + 0.3 * dy, 40)
        best_y0 = float(ys.min())
        best_cost_y = float('inf')
        for cand_y0 in cand_y0s:
            cost_y = 0.0
            for y in ys:
                r = int(round((y - cand_y0) / dy))
                if 0 <= r <= 2:
                    cost_y += (y - (cand_y0 + r * dy))**2
                else:
                    cost_y += 30.0 * (dy**2)
            if cost_y < best_cost_y:
                best_cost_y = cost_y
                best_y0 = float(cand_y0)
        Y0 = best_y0

        # Fit horizontal phase X0
        min_x, max_x = float(xs.min()), float(xs.max())
        best_x0 = min_x
        best_cost_x = float('inf')
        for cand_x0 in np.linspace(min_x - cx, min_x, 100):
            rem = (xs - cand_x0) % cx
            d0 = np.minimum(rem, cx - rem)
            d1 = np.abs(rem - dx)
            cost_x = float(np.sum(np.minimum(d0, d1)**2))
            if cost_x < best_cost_x:
                best_cost_x = cost_x
                best_x0 = float(cand_x0)

        c_start = int(round((min_x - best_x0) / cx))
        c_end = int(round((max_x - best_x0) / cx))

        line_cells = []
        consecutive_empty = 0

        for c in range(c_start, c_end + 1):
            col0_x = best_x0 + c * cx
            col1_x = col0_x + dx
            canonical_nodes_rot = [
                (col0_x, Y0),
                (col0_x, Y0 + dy),
                (col0_x, Y0 + 2.0 * dy),
                (col1_x, Y0),
                (col1_x, Y0 + dy),
                (col1_x, Y0 + 2.0 * dy),
            ]
            dots_present = [0, 0, 0, 0, 0, 0]
            for dot_i, (nx_r, ny_r) in enumerate(canonical_nodes_rot):
                dists, _ = rot_tree.query([nx_r, ny_r], k=1)
                if dists <= node_tol:
                    dots_present[dot_i] = 1
                elif dists <= ambiguous_tol:
                    # Low-threshold neighborhood check
                    # Map back to image coords to check local tophat relief
                    orig_x = cos_t * (nx_r - cx_img) - sin_t * (ny_r - cy_img) + cx_img
                    orig_y = sin_t * (nx_r - cx_img) + cos_t * (ny_r - cy_img) + cy_img
                    ix, iy = int(round(orig_x)), int(round(orig_y))
                    if 0 <= ix < w and 0 <= iy < h:
                        if tophat[iy, ix] >= 6.0:
                            dots_present[dot_i] = 1

            # Bounding box coordinates in rotated space
            bx1_r = col0_x - 0.25 * dx
            by1_r = Y0 - 0.25 * dy
            bx2_r = col1_x + 0.25 * dx
            by2_r = Y0 + 2.25 * dy

            # Convert 4 corners back to original image space for blue bounding box
            box_corners_rot = np.array([
                [bx1_r, by1_r],
                [bx2_r, by1_r],
                [bx2_r, by2_r],
                [bx1_r, by2_r]
            ])
            orig_corners = []
            for (xr, yr) in box_corners_rot:
                ox = cos_t * (xr - cx_img) - sin_t * (yr - cy_img) + cx_img
                oy = sin_t * (xr - cx_img) + cos_t * (yr - cy_img) + cy_img
                orig_corners.append([int(round(ox)), int(round(oy))])
            orig_corners = np.array(orig_corners, dtype=np.int32)

            # Draw blue bounding box for every 2x3 cell grid slot
            cv2.polylines(debug_canvas, [orig_corners], isClosed=True, color=(255, 0, 0), thickness=1)

            is_empty = (sum(dots_present) == 0)
            if is_empty:
                consecutive_empty += 1
                continue

            has_space = (consecutive_empty >= 1 and len(line_cells) > 0)
            consecutive_empty = 0

            bin_str = "".join(str(b) for b in dots_present)
            cell = BrailleGridCell(
                x1=float(orig_corners[:, 0].min()),
                y1=float(orig_corners[:, 1].min()),
                x2=float(orig_corners[:, 0].max()),
                y2=float(orig_corners[:, 1].max()),
                cx=float(orig_corners[:, 0].mean()),
                cy=float(orig_corners[:, 1].mean()),
                dots=dots_present,
                binary_str=bin_str,
                class_index=int(bin_str, 2),
                has_space_before=has_space
            )
            line_cells.append(cell)

        if line_cells:
            u_str, txt = decoder.decode_cells(line_cells)
            all_decoded_lines.append((u_str, txt))
            print(f"Line {line_idx:2d} (y={line_y:6.1f}): uni={u_str} | txt='{txt}'")

    cv2.imwrite("grid_debug.png", debug_canvas)
    print("\nSaved annotated diagnostic image to grid_debug.png")

if __name__ == "__main__":
    run_pipeline()
