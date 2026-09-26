import numpy as np
from PIL import Image
import math

img = Image.open('scratch/test_user_scanned_sheet.jpg').convert('L')
arr = np.array(img)
h, w = arr.shape

# 1. Paper bbox detection
row_profile = np.percentile(arr, 75, axis=1)
col_profile = np.percentile(arr, 75, axis=0)
paper_y = np.where(row_profile > 140)[0]
paper_x = np.where(col_profile > 140)[0]
min_y, max_y = paper_y[0] + 10, paper_y[-1] - 10
min_x, max_x = paper_x[0] + 10, paper_x[-1] - 10

# 2. Local thresholding (integral Bradley-Roth)
# Let's compute integral image
int_img = np.pad(arr, ((1, 0), (1, 0)), mode='constant', constant_values=0)
int_img = np.cumsum(np.cumsum(int_img, axis=0), axis=1)

win = max(16, min(w, h) // 16)
half = win // 2

# Check binarization
bin_mask = np.zeros((h, w), dtype=np.uint8)

for y in range(min_y, max_y):
    y1 = max(0, y - half)
    y2 = min(h - 1, y + half)
    for x in range(min_x, max_x):
        x1 = max(0, x - half)
        x2 = min(w - 1, x + half)
        count = (y2 - y1 + 1) * (x2 - x1 + 1)
        s = int_img[y2 + 1, x2 + 1] - int_img[y1, x2 + 1] - int_img[y2 + 1, x1] + int_img[y1, x1]
        local_mean = s / count
        # Foreground if significantly darker than local background
        if arr[y, x] < local_mean * 0.82:
            bin_mask[y, x] = 1

print(f"Binarized mask foreground pixels: {np.sum(bin_mask)}")

# 3. Connected component labeling
from scipy.ndimage import label
labeled, num_features = label(bin_mask)
print(f"Num connected components: {num_features}")

# 4. Blob analysis: filter for circular blobs and check SOLID vs HOLLOW
candidates = []
for i in range(1, num_features + 1):
    ys, xs = np.where(labeled == i)
    area = len(ys)
    if area < 6 or area > 400:
        continue
    min_bx, max_bx = xs.min(), xs.max()
    min_by, max_by = ys.min(), ys.max()
    bw = max_bx - min_bx + 1
    bh = max_by - min_by + 1
    aspect = bw / float(bh)
    if aspect < 0.45 or aspect > 2.2:
        continue

    cx = float(np.mean(xs))
    cy = float(np.mean(ys))
    radius = math.sqrt(area / math.pi)

    # Now check if this blob is SOLID or HOLLOW:
    # Sample pixels within inner 0.5 * radius of (cx, cy)
    # in the original grayscale image
    icx, icy = int(round(cx)), int(round(cy))
    core_vals = []
    for dy in range(-int(radius * 0.6), int(radius * 0.6) + 1):
        for dx in range(-int(radius * 0.6), int(radius * 0.6) + 1):
            if dx*dx + dy*dy <= (radius * 0.6)**2:
                py = icy + dy
                px = icx + dx
                if 0 <= py < h and 0 <= px < w:
                    core_vals.append(arr[py, px])

    if not core_vals:
        continue

    core_mean = np.mean(core_vals)
    # Also find local background around this dot (distance between radius*1.5 and radius*2.5)
    bg_vals = []
    for dy in range(-int(radius * 2.5), int(radius * 2.5) + 1):
        for dx in range(-int(radius * 2.5), int(radius * 2.5) + 1):
            dist2 = dx*dx + dy*dy
            if (radius * 1.5)**2 <= dist2 <= (radius * 2.5)**2:
                py = icy + dy
                px = icx + dx
                if 0 <= py < h and 0 <= px < w:
                    bg_vals.append(arr[py, px])
    
    local_bg = np.mean(bg_vals) if bg_vals else 180.0
    
    # Is it solid?
    # Solid dot: core_mean is dark relative to local_bg
    # Hollow ring: core_mean is close to local_bg!
    is_solid = core_mean < (local_bg * 0.55) or core_mean < 80

    candidates.append({
        'cx': cx, 'cy': cy, 'radius': radius, 'area': area,
        'core_mean': core_mean, 'local_bg': local_bg, 'is_solid': is_solid
    })

solid_dots = [c for c in candidates if c['is_solid']]
hollow_dots = [c for c in candidates if not c['is_solid']]
print(f"Total candidates: {len(candidates)}, Solid dots: {len(solid_dots)}, Hollow dots: {len(hollow_dots)}")

# Inspect first line of Braille (y between 150 and 195)
line1_solids = [c for c in solid_dots if 150 <= c['cy'] <= 195]
line1_hollows = [c for c in hollow_dots if 150 <= c['cy'] <= 195]
print(f"Line 1: {len(line1_solids)} solid dots, {len(line1_hollows)} hollow dots")
