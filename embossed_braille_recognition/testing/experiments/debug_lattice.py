import cv2
import numpy as np
import sys
from scipy.spatial import cKDTree
from scipy.signal import find_peaks

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')
from braille_ocr.dot_segmenter import EmbossedDot, BrailleGridCell, estimate_global_pitches
from braille_ocr.grade2_decoder import LiblouisGrade2Decoder

def debug_lines(img_path='ml/yolov8_braille/captured_phone_2.jpg'):
    img = cv2.imread(img_path)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape

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
            local_top_thresh = max(6.0, float(np.mean(t_th) + 0.85 * np.std(t_th)))
            local_black_thresh = max(6.0, float(np.mean(t_bh) + 0.85 * np.std(t_bh)))
            bin_crest[y1:y2, x1:x2] = (t_th >= local_top_thresh).astype(np.uint8) * 255
            bin_trough[y1:y2, x1:x2] = (t_bh >= local_black_thresh).astype(np.uint8) * 255

    num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
    num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)

    min_radius, max_radius = 2.0, 13.0
    min_area = np.pi * (min_radius**2) * 0.4
    max_area = np.pi * (max_radius**2) * 1.6

    crests = []
    for i in range(1, num_c):
        area = stats_c[i, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            bw = stats_c[i, cv2.CC_STAT_WIDTH]
            bh_c = stats_c[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh_c) if bh_c > 0 else 0
            if 0.55 <= aspect <= 1.8:
                crests.append((cent_c[i][0], cent_c[i][1], float(area), float(tophat[int(cent_c[i][1]), int(cent_c[i][0])])))

    troughs = []
    for i in range(1, num_t):
        area = stats_t[i, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            bw = stats_t[i, cv2.CC_STAT_WIDTH]
            bh_t = stats_t[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh_t) if bh_t > 0 else 0
            if 0.55 <= aspect <= 1.8:
                troughs.append((cent_t[i][0], cent_t[i][1], float(area), float(blackhat[int(cent_t[i][1]), int(cent_t[i][0])])))

    dots = []
    if crests and troughs:
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

    dots.sort(key=lambda d: d.contrast, reverse=True)
    grid_nms = {}
    kept_dots = []
    for d in dots:
        gx, gy = int(d.x // 4.5), int(d.y // 4.5)
        if any((gx + ox, gy + oy) in grid_nms for ox in (-1, 0, 1) for oy in (-1, 0, 1)):
            continue
        grid_nms[(gx, gy)] = d
        kept_dots.append(d)

    dx, dy, cx = estimate_global_pitches(kept_dots)
    print(f"Pitches: dx={dx:.1f}, dy={dy:.1f}, cx={cx:.1f}")

    # Peak detection for line baselines
    y_coords = np.array([d.y for d in kept_dots], dtype=np.float32)
    print(f"Total dots: {len(y_coords)}")
    
    # Histogram of Y coordinates between 20 and 150
    counts, bin_edges = np.histogram(y_coords[(y_coords >= 20) & (y_coords <= 150)], bins=26)
    print("Y histogram [20..150]:")
    for cnt, b0, b1 in zip(counts, bin_edges[:-1], bin_edges[1:]):
        bar = '#' * cnt
        print(f"  [{b0:5.1f} - {b1:5.1f}]: {cnt:2d} {bar}")

    # Test different sigmas and min_dists
    for test_sigma in [3.0, 5.0, 7.0, 9.0]:
        y_grid = np.arange(20.0, 150.0, 1.0, dtype=np.float32)
        dens = np.zeros_like(y_grid)
        sub_y = y_coords[(y_coords >= 15) & (y_coords <= 155)]
        for y in sub_y:
            dens += np.exp(-0.5 * ((y_grid - y) / test_sigma)**2)
        pks, _ = find_peaks(dens, distance=25, height=np.mean(dens)*0.2)
        peak_ys = [f"{y_grid[p]:.1f}" for p in pks]
        print(f"Sigma={test_sigma:.1f}, min_dist=25: peaks={peak_ys}")

    # Test Line 0 specifically at y=46.4
    l0_y = 46.4
    pts0 = np.array([[d.x, d.y] for d in kept_dots if abs(d.y - l0_y) <= 20], dtype=np.float32)
    print(f"\nLine 0 (y={l0_y:.1f}) has {len(pts0)} dots.")
    
    # Check Y0 fit
    ys0 = pts0[:, 1]
    xs0 = pts0[:, 0]
    cand_y0s = np.linspace(l0_y - dy, l0_y + 0.3 * dy, 30)
    best_y0 = float(ys0.min())
    best_cost_y = float('inf')
    for cand_y0 in cand_y0s:
        cost_y = 0.0
        for y in ys0:
            r = int(round((y - cand_y0) / dy))
            if 0 <= r <= 2:
                cost_y += (y - (cand_y0 + r * dy))**2
            else:
                cost_y += 25.0 * (dy**2)
        if cost_y < best_cost_y:
            best_cost_y = cost_y
            best_y0 = float(cand_y0)
    print(f"Line 0 best Y0: {best_y0:.1f}, rows at: {best_y0:.1f}, {best_y0+dy:.1f}, {best_y0+2*dy:.1f}")

    # Check horizontal phase
    min_x, max_x = float(xs0.min()), float(xs0.max())
    best_x0 = min_x
    best_cost_x = float('inf')
    for cand_x0 in np.linspace(min_x - cx, min_x, 100):
        rem = (xs0 - cand_x0) % cx
        d0 = np.minimum(rem, cx - rem)
        d1 = np.abs(rem - dx)
        cost_x = float(np.sum(np.minimum(d0, d1)**2))
        if cost_x < best_cost_x:
            best_cost_x = cost_x
            best_x0 = float(cand_x0)
    print(f"Line 0 best X0: {best_x0:.1f}")

    c_start = int(round((min_x - best_x0) / cx))
    c_end = int(round((max_x - best_x0) / cx))
    print(f"Line 0 cell range: {c_start} to {c_end} ({c_end - c_start + 1} cells)")

    dot_tree = cKDTree(pts0)
    node_tol = dx * 0.46
    decoder = LiblouisGrade2Decoder()
    line_cells = []
    consecutive_empty = 0
    for c in range(c_start, c_end + 1):
        col0_x = best_x0 + c * cx
        col1_x = col0_x + dx
        canonical_nodes = [
            (col0_x, best_y0),
            (col0_x, best_y0 + dy),
            (col0_x, best_y0 + 2.0 * dy),
            (col1_x, best_y0),
            (col1_x, best_y0 + dy),
            (col1_x, best_y0 + 2.0 * dy),
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
        by1 = best_y0 - 0.25 * dy
        bx2 = col1_x + 0.25 * dx
        by2 = best_y0 + 2.25 * dy
        cell = BrailleGridCell(
            x1=bx1, y1=by1, x2=bx2, y2=by2, cx=(bx1+bx2)/2, cy=(by1+by2)/2,
            dots=dots_present, binary_str=bin_str, class_index=int(bin_str, 2),
            has_space_before=has_space
        )
        line_cells.append(cell)
        print(f"Cell {c:2d}: dots={dots_present} uni={cell.unicode_char} space={has_space}")

    u_str, txt = decoder.decode_cells(line_cells)
    print(f"\nDecoded Line 0: uni={u_str} | txt='{txt}'")


if __name__ == "__main__":
    debug_lines()
