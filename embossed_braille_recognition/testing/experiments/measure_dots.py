import numpy as np
from PIL import Image

img = Image.open('scratch/test_user_scanned_sheet.jpg').convert('L')
arr = np.array(img)
h, w = arr.shape

# Let's find the paper boundary first!
# The paper is white/light gray (mean > 160-200), whereas the table/background is dark (< 100).
# Let's inspect row and column averages
row_means = arr.mean(axis=1)
col_means = arr.mean(axis=0)

paper_mask = arr > 120
# Let's find the bounding box of the paper
paper_rows = np.where(paper_mask.sum(axis=1) > w * 0.4)[0]
paper_cols = np.where(paper_mask.sum(axis=0) > h * 0.4)[0]
min_y, max_y = paper_rows[0], paper_rows[-1]
min_x, max_x = paper_cols[0], paper_cols[-1]
print(f"Paper bbox approx: y=[{min_y}, {max_y}], x=[{min_x}, {max_x}]")

# Now let's inspect local binarization in paper region
# Let's look at the first Braille line: y in [150, 195], x in [130, 420]
# Sentence 1: "1. I AM HAPPY."
# Let's print out what is happening in this crop:
crop = arr[150:195, 130:420]
paper_val = np.median(crop)
print(f"Crop median (paper bg): {paper_val}")

# Let's find all circular features in this crop
# Let's print the actual cells in this region!
# 'I' cell: x in [135, 165], y in [155, 185]
cell_I = arr[155:185, 135:165]
# Cell I has 6 dot positions:
# dot 1: (x=142, y=160), dot 4: (x=156, y=160)
# dot 2: (x=142, y=170), dot 5: (x=156, y=170)
# dot 3: (x=142, y=180), dot 6: (x=156, y=180)

# Let's sample luminance around each of these 6 positions:
for (name, r, c) in [
    ("Dot 1 (hollow)", 160, 142),
    ("Dot 4 (SOLID)",  160, 156),
    ("Dot 2 (SOLID)",  170, 142),
    ("Dot 5 (hollow)", 170, 156),
    ("Dot 3 (hollow)", 180, 142),
    ("Dot 6 (hollow)", 180, 156),
]:
    # Center pixel (r-1..r+1, c-1..c+1)
    center_lum = arr[r-1:r+2, c-1:c+2].mean()
    # Ring pixel (radius 3 to 5)
    ys, xs = np.ogrid[-5:6, -5:6]
    dist = np.sqrt(ys**2 + xs**2)
    ring_mask = (dist >= 3) & (dist <= 5)
    ring_pixels = arr[r-5:r+6, c-5:c+6][ring_mask]
    ring_lum = ring_pixels.mean()
    print(f"{name:16s} at y={r}, x={c}: center_lum={center_lum:.1f}, ring_lum={ring_lum:.1f}, diff={ring_lum - center_lum:.1f}")
