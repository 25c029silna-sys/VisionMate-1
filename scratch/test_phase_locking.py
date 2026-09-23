import cv2
import numpy as np
import sys
from scipy.spatial import cKDTree

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')
from braille_ocr.dot_segmenter import BrailleGridCell, estimate_global_pitches
from braille_ocr.grade2_decoder import LiblouisGrade2Decoder

# Load YOLO line 0 to see ground truth
from braille_ocr.pipeline import BrailleOCRPipeline
pipe = BrailleOCRPipeline('app/assets/models/yolov8_braille.tflite')
res = pipe.process_image('ml/yolov8_braille/captured_phone_2.jpg')
yolo_l0 = res['grid_lines'][0]
print("YOLO Line 0:")
for c in yolo_l0:
    print(f"  Cell {c.unicode_char}: cx={c.cx:.1f} col0={c.cx-12:.1f}")

# Extract dots in line 0 from adaptive detector
raw = pipe._load_image('ml/yolov8_braille/captured_phone_2.jpg')
gray = cv2.cvtColor(raw, cv2.COLOR_BGR2GRAY)
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
        bin_crest[y1:y2, x1:x2] = (t_th >= max(7.0, float(np.mean(t_th) + 0.95 * np.std(t_th)))).astype(np.uint8) * 255
        bin_trough[y1:y2, x1:x2] = (t_bh >= max(7.0, float(np.mean(t_bh) + 0.95 * np.std(t_bh)))).astype(np.uint8) * 255

num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)
crests = [cent_c[i] for i in range(1, num_c) if 10 <= stats_c[i, cv2.CC_STAT_AREA] <= 350 and 0.55 <= stats_c[i, cv2.CC_STAT_WIDTH]/max(1, stats_c[i, cv2.CC_STAT_HEIGHT]) <= 1.8]
troughs = [cent_t[i] for i in range(1, num_t) if 10 <= stats_t[i, cv2.CC_STAT_AREA] <= 350 and 0.55 <= stats_t[i, cv2.CC_STAT_WIDTH]/max(1, stats_t[i, cv2.CC_STAT_HEIGHT]) <= 1.8]
tree = cKDTree(np.array(troughs))
dists, idxs = tree.query(np.array(crests))
dots = [crests[i] for i, d in enumerate(dists) if 2.0 <= d <= 20.0]
pts = np.array(dots)

# Dots in Line 0 (accounting for tilt: y ≈ 46.4 - 0.025 * x)
pts_l0 = []
for p in pts:
    expected_y = 48.0 - 0.025 * p[0]
    if abs(p[1] - expected_y) <= 18.0:
        pts_l0.append(p)
pts_l0 = np.array(pts_l0)
print(f"\nAdaptive dots in Line 0: {len(pts_l0)}")

dx = 12.8
cx = 40.5
dy = 12.8

# Find horizontal pairs with dx distance
dx_pairs = []
for i in range(len(pts_l0)):
    for j in range(len(pts_l0)):
        diff_x = pts_l0[j, 0] - pts_l0[i, 0]
        diff_y = abs(pts_l0[j, 1] - pts_l0[i, 1])
        if (dx * 0.75) <= diff_x <= (dx * 1.25) and diff_y <= 5.0:
            dx_pairs.append((pts_l0[i, 0], pts_l0[j, 0]))

print(f"Found {len(dx_pairs)} horizontal intra-cell dot pairs in Line 0.")
phases = [p[0] % cx for p in dx_pairs]
# Circular mean / median
rads = np.array(phases) * (2 * np.pi / cx)
mean_rad = np.arctan2(np.mean(np.sin(rads)), np.mean(np.cos(rads))) % (2 * np.pi)
best_phase = mean_rad * (cx / (2 * np.pi))
print(f"Locked Col 0 phase X0 % cx: {best_phase:.2f} (from {len(phases)} intra-cell pairs)")

# Compare with YOLO Line 0 Col 0 phase
yolo_phases = [(c.cx - 12.0) % cx for c in yolo_l0]
yolo_rads = np.array(yolo_phases) * (2 * np.pi / cx)
yolo_mean_phase = (np.arctan2(np.mean(np.sin(yolo_rads)), np.mean(np.cos(yolo_rads))) % (2 * np.pi)) * (cx / (2 * np.pi))
print(f"YOLO Col 0 phase X0 % cx:   {yolo_mean_phase:.2f}")
print(f"Phase difference: {abs(best_phase - yolo_mean_phase):.2f} px")
