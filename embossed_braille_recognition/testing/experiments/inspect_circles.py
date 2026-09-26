import numpy as np
from PIL import Image

img = Image.open('scratch/test_user_scanned_sheet.jpg').convert('L')
arr = np.array(img)

# In crop y in [150, 195], x in [130, 420]
# Cell 1 ('I'):
# Dot 1 (Hollow): y=165, x=138
# Dot 4 (Solid):  y=165, x=154
# Dot 2 (Solid):  y=175, x=138
# Dot 5 (Hollow): y=175, x=154
# Dot 3 (Hollow): y=185, x=138
# Dot 6 (Hollow): y=185, x=154

def inspect_circle(name, cy, cx):
    sub = arr[cy-5:cy+6, cx-5:cx+6]
    core = arr[cy-1:cy+2, cx-1:cx+2]
    outer = []
    for dy in range(-5, 6):
        for dx in range(-5, 6):
            r = np.sqrt(dx*dx + dy*dy)
            if 3.0 <= r <= 5.0:
                outer.append(arr[cy+dy, cx+dx])
    bg = []
    for dy in range(-7, 8):
        for dx in range(-7, 8):
            r = np.sqrt(dx*dx + dy*dy)
            if 5.5 <= r <= 7.5:
                bg.append(arr[cy+dy, cx+dx])
    print(f"\n{name} at ({cx}, {cy}):")
    print(f"  Core (3x3) mean: {core.mean():.1f}, min: {core.min()}, max: {core.max()}")
    print(f"  Ring mean: {np.mean(outer):.1f}")
    print(f"  Local BG mean: {np.mean(bg):.1f}")
    print("  Submatrix (11x11):")
    for row in sub:
        print("  " + " ".join([f"{v:3d}" for v in row]))

inspect_circle("Letter I - Dot 1 (Hollow)", 165, 138)
inspect_circle("Letter I - Dot 4 (Solid)",  165, 154)
inspect_circle("Letter I - Dot 2 (Solid)",  175, 138)
inspect_circle("Letter I - Dot 5 (Hollow)", 175, 154)
