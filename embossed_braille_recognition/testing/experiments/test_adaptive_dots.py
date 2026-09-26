import cv2
import numpy as np
import sys
from scipy.spatial import cKDTree
from scipy.signal import find_peaks

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')
from braille_ocr.dot_segmenter import EmbossedDot, estimate_global_pitches
from braille_ocr.grade2_decoder import LiblouisGrade2Decoder

def test_adaptive_detector(img_path='ml/yolov8_braille/captured_phone_2.jpg'):
    img = cv2.imread(img_path)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape

    # 1. CLAHE + Gaussian smoothing
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    smoothed = cv2.GaussianBlur(enhanced, (5, 5), 1.0)

    # 2. Morphological Top-Hat & Black-Hat
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
    tophat = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)
    blackhat = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)

    # 3. Local adaptive thresholding per tile
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

    min_area = 10.0
    max_area = 350.0

    crests = []
    for i in range(1, num_c):
        area = stats_c[i, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            bw = stats_c[i, cv2.CC_STAT_WIDTH]
            bh = stats_c[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh) if bh > 0 else 0
            if 0.55 <= aspect <= 1.80:
                cx_c, cy_c = cent_c[i][0], cent_c[i][1]
                val = float(tophat[int(cy_c), int(cx_c)])
                crests.append((cx_c, cy_c, float(area), val))

    troughs = []
    for i in range(1, num_t):
        area = stats_t[i, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            bw = stats_t[i, cv2.CC_STAT_WIDTH]
            bh = stats_t[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh) if bh > 0 else 0
            if 0.55 <= aspect <= 1.80:
                cx_t, cy_t = cent_t[i][0], cent_t[i][1]
                val = float(blackhat[int(cy_t), int(cx_t)])
                troughs.append((cx_t, cy_t, float(area), val))

    print(f"Candidate crests: {len(crests)}, troughs: {len(troughs)}")

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

    print(f"Adaptive dots kept after NMS: {len(kept_dots)}")

    dx, dy, cx = estimate_global_pitches(kept_dots)
    print(f"Pitches: dx={dx:.1f}, dy={dy:.1f}, cx={cx:.1f}")

    y_coords = np.array([d.y for d in kept_dots], dtype=np.float32)
    # Detect raw lines via Y-projection KDE
    y_min, y_max = float(y_coords.min()), float(y_coords.max())
    y_grid = np.arange(y_min - dy, y_max + dy, 1.0, dtype=np.float32)
    density = np.zeros_like(y_grid)
    sigma = max(4.0, dy * 0.70)
    for y in y_coords:
        density += np.exp(-0.5 * ((y_grid - y) / sigma)**2)

    min_dist = max(int(round(dy * 3.0)), 15)
    peaks, _ = find_peaks(density, distance=min_dist, height=float(np.mean(density) * 0.25))
    raw_lines = sorted([float(y_grid[p]) for p in peaks])
    print(f"Raw lines detected: {len(raw_lines)}")

    # Interpolate missing lines based on median line pitch
    diffs = np.diff(raw_lines)
    valid_diffs = diffs[(diffs >= dy * 2.5) & (diffs <= dy * 8.0)]
    med_lh = float(np.median(valid_diffs)) if len(valid_diffs) > 0 else (dy * 4.5)
    print(f"Median line height LH: {med_lh:.1f}")

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

    print(f"Lines after interpolation ({len(interpolated_lines)} lines):")

    dot_pts = np.array([[d.x, d.y] for d in kept_dots], dtype=np.float32)
    dot_tree = cKDTree(dot_pts)
    decoder = LiblouisGrade2Decoder()
    from braille_ocr.dot_segmenter import BrailleGridCell

    for line_idx, line_y in enumerate(interpolated_lines):
        m_line = np.abs(dot_pts[:, 1] - line_y) <= (dy * 1.5)
        pts_in_line = dot_pts[m_line]
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

        node_tol = dx * 0.46
        line_cells = []
        consecutive_empty = 0

        for c in range(c_start, c_end + 1):
            col0_x = best_x0 + c * cx
            col1_x = col0_x + dx
            canonical_nodes = [
                (col0_x, Y0),
                (col0_x, Y0 + dy),
                (col0_x, Y0 + 2.0 * dy),
                (col1_x, Y0),
                (col1_x, Y0 + dy),
                (col1_x, Y0 + 2.0 * dy),
            ]
            dots_present = [0, 0, 0, 0, 0, 0]
            for dot_i, (nx, ny) in enumerate(canonical_nodes):
                dists, _ = dot_tree.query([nx, ny], k=1)
                if dists <= node_tol:
                    dots_present[dot_i] = 1

            is_empty = (sum(dots_present) == 0)
            if is_empty:
                consecutive_empty += 1
                continue

            has_space = (consecutive_empty >= 1 and len(line_cells) > 0)
            consecutive_empty = 0

            bin_str = "".join(str(b) for b in dots_present)
            bx1 = col0_x - 0.25 * dx
            by1 = Y0 - 0.25 * dy
            bx2 = col1_x + 0.25 * dx
            by2 = Y0 + 2.25 * dy

            cell = BrailleGridCell(
                x1=bx1, y1=by1, x2=bx2, y2=by2, cx=(bx1+bx2)/2, cy=(by1+by2)/2,
                dots=dots_present, binary_str=bin_str, class_index=int(bin_str, 2),
                has_space_before=has_space
            )
            line_cells.append(cell)

        if line_cells:
            u_str, txt = decoder.decode_cells(line_cells)
            print(f"Line {line_idx:2d} (y={line_y:6.1f}): uni={u_str} | txt='{txt}'")


if __name__ == "__main__":
    test_adaptive_detector()
