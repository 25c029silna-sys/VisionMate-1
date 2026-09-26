import numpy as np
from PIL import Image

img = Image.open('scratch/test_user_scanned_sheet.jpg').convert('L')
arr = np.array(img)
h, w = arr.shape
print(f"Shape: {w}x{h}, min={arr.min()}, max={arr.max()}, mean={arr.mean():.1f}")

# Look at histogram of image
hist, bins = np.histogram(arr, bins=10, range=(0, 256))
print("Histogram:", hist)

# Let's inspect rows from top to bottom
# In sentence 1: around y = 160 to 200
# Let's find where the dots for Sentence 1 are
# Let's sample a crop of the first Braille cell under '1. I AM HAPPY.'
# '1. I AM HAPPY.' is at the top left of the sheet
# Let's print out crops around y = 150..220, x = 120..220
print("\nCrop near first cell (sentence 1, letter 'I'):")
sub = arr[150:190, 130:170]
print("Sub min, max, mean:", sub.min(), sub.max(), sub.mean())

# Let's find dark pixels in this region
for y in range(150, 190, 2):
    row_str = "".join(["#" if val < 100 else ("o" if val < 180 else " ") for val in arr[y, 130:175:2]])
    print(f"{y:3d}: {row_str}")
