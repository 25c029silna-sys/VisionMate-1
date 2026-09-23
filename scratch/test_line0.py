import cv2
import numpy as np
import sys
from scipy.spatial import cKDTree

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')
from braille_ocr.dot_segmenter import BrailleGridCell, estimate_global_pitches, EmbossedDot
from braille_ocr.grade2_decoder import LiblouisGrade2Decoder

img = cv2.imread('ml/yolov8_braille/captured_phone_2.jpg')
gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
enhanced = clahe.apply(gray)
smoothed = cv2.GaussianBlur(enhanced, (5, 5), 1.0)
k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
tophat = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)
blackhat = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)

h, w = gray.shape
tiles_y, tiles_x = max(2, h // 160), max(2, w // 160)
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
crests = [cent_c[i] for i in range(1, num_c) if 10 <= stats_c[i, cv2.CC_STAT_AREA] <= 350 and 0.55 <= stats_c[i, cv2.CC_STAT_WIDTH]/max(1, stats_c[i, cv2.CC_STAT_HEIGHT]) <= 1.8]
troughs = [cent_t[i] for i in range(1, num_t) if 10 <= stats_t[i, cv2.CC_STAT_AREA] <= 350 and 0.55 <= stats_t[i, cv2.CC_STAT_WIDTH]/max(1, stats_t[i, cv2.CC_STAT_HEIGHT]) <= 1.8]
tree = cKDTree(np.array(troughs))
dists, idxs = tree.query(np.array(crests))
dots = [crests[i] for i, d in enumerate(dists) if 2.0 <= d <= 20.0]
pts = np.array(dots)

# Dots around y=46.4
pts_l0 = pts[np.abs(pts[:, 1] - 46.4) <= 18.0]
print(f"Dots in line y=46.4: {len(pts_l0)}")

dx, dy, cx = 13.5, 13.5, 41.0
xs = pts_l0[:, 0]
ys = pts_l0[:, 1]

# Estimate slope m of the line from dot regression
slope, intercept = np.polyfit(pts_l0[:, 0], pts_l0[:, 1], 1)
print(f"Line slope m: {slope:.5f}, angle: {np.degrees(np.arctan(slope)):.3f} deg")

# Row 0 baseline relative to intercept
# Cy of cell is ~ intercept, so Row 0 is at intercept - dy
Y0_intercept = intercept - dy

# Best horizontal phase X0
min_x, max_x = float(xs.min()), float(xs.max())
best_x0 = min_x
best_cost_x = float('inf')
for cand_x0 in np.linspace(min_x - cx, min_x, 100):
    rem = (xs - cand_x0) % cx
    d0 = np.minimum(rem, cx - rem)
    d1 = np.abs(rem - dx)
    cost = float(np.sum(np.minimum(d0, d1)**2))
    if cost < best_cost_x:
        best_cost_x = cost
        best_x0 = float(cand_x0)

dot_tree = cKDTree(pts_l0)
c_start = int(round((min_x - best_x0) / cx))
c_end = int(round((max_x - best_x0) / cx))
line_cells = []
consecutive_empty = 0
for c in range(c_start, c_end + 1):
    col0_x = best_x0 + c * cx
    col1_x = col0_x + dx
    # Sloped Y0 for this cell!
    cell_y0 = Y0_intercept + slope * col0_x
    canonical_nodes = [
        (col0_x, cell_y0), (col0_x, cell_y0 + dy), (col0_x, cell_y0 + 2*dy),
        (col1_x, cell_y0), (col1_x, cell_y0 + dy), (col1_x, cell_y0 + 2*dy)
    ]
    dots_present = [0]*6
    for dot_i, (nx, ny) in enumerate(canonical_nodes):
        d, _ = dot_tree.query([nx, ny], k=1)
        if d <= dx * 0.46:
            dots_present[dot_i] = 1
    if sum(dots_present) == 0:
        consecutive_empty += 1
        continue
    has_space = (consecutive_empty >= 1 and len(line_cells) > 0)
    consecutive_empty = 0
    bin_str = ''.join(str(b) for b in dots_present)
    line_cells.append(BrailleGridCell(
        x1=col0_x, y1=cell_y0, x2=col1_x+dx, y2=cell_y0+2*dy, cx=col0_x+dx/2, cy=cell_y0+dy,
        dots=dots_present, binary_str=bin_str, class_index=int(bin_str, 2),
        has_space_before=has_space
    ))


dec = LiblouisGrade2Decoder()
u, t = dec.decode_cells(line_cells)
print(f"Decoded: uni={u}")
print(f"Text:    txt='{t}'")
