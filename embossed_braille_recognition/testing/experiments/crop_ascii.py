import numpy as np
from PIL import Image

img = Image.open('scratch/test_user_scanned_sheet.jpg').convert('L')
arr = np.array(img)

# Let's binarize arr[150:195, 130:420] using Bradley / local threshold
crop = arr[150:195, 130:420]
h, w = crop.shape
bg_mean = np.mean(crop)
print("Crop shape:", h, w, "mean:", bg_mean)

# Print a visual ASCII map of crop with threshold
thresh = bg_mean * 0.85
print("Visual map:")
for y in range(0, h, 2):
    line = "".join(["#" if crop[y, x] < thresh else "." for x in range(0, min(w, 100), 2)])
    print(f"{y:2d}: {line}")
