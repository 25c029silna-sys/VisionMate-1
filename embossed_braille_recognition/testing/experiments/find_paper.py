import numpy as np
from PIL import Image

img = Image.open('scratch/test_user_scanned_sheet.jpg').convert('L')
arr = np.array(img)
h, w = arr.shape

row_profile = np.percentile(arr, 75, axis=1)
col_profile = np.percentile(arr, 75, axis=0)

paper_y = np.where(row_profile > 140)[0]
paper_x = np.where(col_profile > 140)[0]
print(f"Paper y: {paper_y[0]} to {paper_y[-1]}")
print(f"Paper x: {paper_x[0]} to {paper_x[-1]}")
