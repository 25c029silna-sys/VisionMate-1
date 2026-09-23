import cv2
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')

from braille_ocr.dot_segmenter import detect_embossed_dots, estimate_global_pitches, EmbossedDot, BrailleGridCell
from braille_ocr.grade2_decoder import LiblouisGrade2Decoder, dots_to_unicode
from braille_ocr import louis

# Load image
img = cv2.imread('ml/yolov8_braille/captured_phone_2.jpg')
gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

# 1. Adaptive dot detection with CLAHE
clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
enhanced = clahe.apply(gray)
k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
tophat = cv2.morphologyEx(enhanced, cv2.MORPH_TOPHAT, k)
blackhat = cv2.morphologyEx(enhanced, cv2.MORPH_BLACKHAT, k)

h, w = gray.shape
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
        local_top_thresh = max(5.0, float(np.mean(t_th) + 0.75 * np.std(t_th)))
        local_black_thresh = max(5.0, float(np.mean(t_bh) + 0.75 * np.std(t_bh)))
        bin_crest[y1:y2, x1:x2] = (t_th >= local_top_thresh).astype(np.uint8) * 255
        bin_trough[y1:y2, x1:x2] = (t_bh >= local_black_thresh).astype(np.uint8) * 255

num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)

min_radius, max_radius = 2.0, 14.0
min_area = np.pi * (min_radius**2) * 0.35
max_area = np.pi * (max_radius**2) * 1.8

crests = []
for i in range(1, num_c):
    area = stats_c[i, cv2.CC_STAT_AREA]
    if min_area <= area <= max_area:
        bw = stats_c[i, cv2.CC_STAT_WIDTH]
        bh_c = stats_c[i, cv2.CC_STAT_HEIGHT]
        aspect = bw / float(bh_c) if bh_c > 0 else 0
        if 0.5 <= aspect <= 2.0:
            cx, cy = cent_c[i][0], cent_c[i][1]
            crests.append((cx, cy, float(area), float(tophat[int(cy), int(cx)])))

troughs = []
for i in range(1, num_t):
    area = stats_t[i, cv2.CC_STAT_AREA]
    if min_area <= area <= max_area:
        bw = stats_t[i, cv2.CC_STAT_WIDTH]
        bh_t = stats_t[i, cv2.CC_STAT_HEIGHT]
        aspect = bw / float(bh_t) if bh_t > 0 else 0
        if 0.5 <= aspect <= 2.0:
            cx, cy = cent_t[i][0], cent_t[i][1]
            troughs.append((cx, cy, float(area), float(blackhat[int(cy), int(cx)])))

from scipy.spatial import cKDTree

dots = []
if len(crests) > 0 and len(troughs) > 0:
    troughs_arr = np.array([[t[0], t[1]] for t in troughs], dtype=np.float32)
    crests_arr = np.array([[c[0], c[1]] for c in crests], dtype=np.float32)
    trough_tree = cKDTree(troughs_arr)
    dists, min_indices = trough_tree.query(crests_arr, k=1)

    for i, d in enumerate(dists):
        if min_radius <= d <= (max_radius * 2.2):
            c_x, c_y = crests[i][0], crests[i][1]
            c_val = crests[i][3]
            min_idx = min_indices[i]
            t_x, t_y = troughs[min_idx][0], troughs[min_idx][1]
            dot_x = 0.7 * c_x + 0.3 * t_x
            dot_y = 0.7 * c_y + 0.3 * t_y
            dots.append(EmbossedDot(x=dot_x, y=dot_y, radius=float(d/2.0), contrast=c_val, vector_dx=t_x-c_x, vector_dy=t_y-c_y))

# Fast O(N) spatial grid NMS on dots
dots.sort(key=lambda d: d.contrast, reverse=True)
grid_nms = {}
kept_dots = []
cell_sz = 4.0
for d in dots:
    gx = int(d.x // cell_sz)
    gy = int(d.y // cell_sz)
    occupied = False
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            if (gx + ox, gy + oy) in grid_nms:
                occupied = True
                break
        if occupied:
            break
    if not occupied:
        grid_nms[(gx, gy)] = d
        kept_dots.append(d)

print(f"Total adaptive dots detected: {len(kept_dots)}")

# 2. Pitches
dx, dy, cx = estimate_global_pitches(kept_dots)
print(f"Global pitches: dx={dx:.1f}, dy={dy:.1f}, cx={cx:.1f}")

# 3. Line baselines with KDE & missing line interpolation
y_coords = np.array([d.y for d in kept_dots], dtype=np.float32)
y_min, y_max = float(y_coords.min()), float(y_coords.max())
y_grid = np.arange(y_min - dy, y_max + dy, 1.0, dtype=np.float32)
density = np.zeros_like(y_grid)
sigma = max(4.0, dy * 0.45)
for y in y_coords:
    density += np.exp(-0.5 * ((y_grid - y) / sigma)**2)

from scipy.signal import find_peaks
min_dist = max(int(round(dy * 2.6)), 5)
peak_indices, _ = find_peaks(density, distance=min_dist, height=float(np.mean(density) * 0.20))
raw_lines = [float(y_grid[p]) for p in peak_indices]
raw_lines.sort()

# Dominant median line pitch
diffs = np.diff(raw_lines)
valid_diffs = diffs[(diffs >= dy * 2.5) & (diffs <= dy * 8.0)]
med_lh = float(np.median(valid_diffs)) if len(valid_diffs) > 0 else (dy * 4.8)
print(f"Raw line count: {len(raw_lines)}, median LH={med_lh:.1f}")

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
print(f"Interpolated line count: {len(interpolated_lines)}")

# 4. Continuous lattice projection across each line
from scipy.spatial import cKDTree
dot_pts = np.array([[d.x, d.y] for d in kept_dots], dtype=np.float32)
dot_tree = cKDTree(dot_pts) if len(dot_pts) > 0 else None

decoder = LiblouisGrade2Decoder()
translated_lines = []
raw_braille_lines = []

for line_idx, line_y in enumerate(interpolated_lines):
    # Find dots belonging to this line
    m_line = np.abs(dot_pts[:, 1] - line_y) <= (dy * 1.6)
    pts_in_line = dot_pts[m_line]
    if len(pts_in_line) < 2:
        continue
    
    xs = pts_in_line[:, 0]
    ys = pts_in_line[:, 1]
    
    # Estimate Y0 (Row 0)
    min_y = float(ys.min())
    best_y0 = min_y
    best_cost_y = float('inf')
    for cand_y0 in np.linspace(line_y - dy, line_y, 40):
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
    for cand_x0 in np.linspace(min_x - cx, min_x, 80):
        rem = (xs - cand_x0) % cx
        d0 = np.minimum(rem, cx - rem)
        d1 = np.abs(rem - dx)
        dist_min = np.minimum(d0, d1)
        cost_x = float(np.sum(np.minimum(dist_min**2, (dx * 0.7)**2)))
        if cost_x < best_cost_x:
            best_cost_x = cost_x
            best_x0 = float(cand_x0)
    
    # Continuous candidate grid slots
    c_start = int(round((min_x - best_x0) / cx))
    c_end = int(round((max_x - best_x0) / cx))
    
    node_tol = dx * 0.48
    line_cells = []
    consecutive_empty = 0

    for c in range(c_start, c_end + 1):
        col0_x = best_x0 + c * cx
        col1_x = col0_x + dx
        
        # 6 canonical node coordinates
        canonical_nodes = [
            (col0_x, Y0),              # Dot 1: Row 0, Col 0
            (col0_x, Y0 + dy),         # Dot 2: Row 1, Col 0
            (col0_x, Y0 + 2.0 * dy),   # Dot 3: Row 2, Col 0
            (col1_x, Y0),              # Dot 4: Row 0, Col 1
            (col1_x, Y0 + dy),         # Dot 5: Row 1, Col 1
            (col1_x, Y0 + 2.0 * dy),   # Dot 6: Row 2, Col 1
        ]
        
        dots_present = [0, 0, 0, 0, 0, 0]
        for dot_i, (nx, ny) in enumerate(canonical_nodes):
            if dot_tree is not None:
                dists, _ = dot_tree.query([nx, ny], k=1)
                if dists <= node_tol:
                    dots_present[dot_i] = 1
                else:
                    # Ambiguous dot neighborhood relief check
                    ix, iy = int(round(nx)), int(round(ny))
                    if 0 <= iy < h and 0 <= ix < w:
                        patch = tophat[max(0, iy - 2):min(h, iy + 3), max(0, ix - 2):min(w, ix + 3)]
                        if patch.size > 0 and np.max(patch) > 18.0:
                            dots_present[dot_i] = 1
                            
        is_empty = (sum(dots_present) == 0)
        if is_empty:
            consecutive_empty += 1
            continue
            
        has_space = (consecutive_empty >= 1 and len(line_cells) > 0)
        consecutive_empty = 0
        
        bin_str = "".join(str(b) for b in dots_present)
        cell = BrailleGridCell(
            x1=col0_x - 0.25 * dx,
            y1=Y0 - 0.25 * dy,
            x2=col1_x + 0.25 * dx,
            y2=Y0 + 2.0 * dy + 0.25 * dy,
            cx=(col0_x + col1_x) / 2.0,
            cy=Y0 + dy,
            dots=dots_present,
            binary_str=bin_str,
            class_index=int(bin_str, 2),
            has_space_before=has_space
        )
        line_cells.append(cell)
        
    if line_cells:
        u_str, txt = decoder.decode_cells(line_cells)
        raw_braille_lines.append(u_str)
        translated_lines.append(txt)
        print(f"Line {line_idx:2d} (y={line_y:.0f}): uni={u_str} | txt={txt}")

print("\n=== FULL TRANSLATION ===")
print("\n".join(translated_lines))
