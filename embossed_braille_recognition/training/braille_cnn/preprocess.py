import cv2
import numpy as np
from typing import List, Tuple

def order_points(pts: np.ndarray) -> np.ndarray:
    """Orders 4 contour coordinates as top-left, top-right, bottom-right, bottom-left."""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]

    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def four_point_transform(image: np.ndarray, pts: np.ndarray) -> np.ndarray:
    """Applies perspective warp transformation to obtain a top-down view of the Braille page."""
    rect = order_points(pts)
    (tl, tr, br, bl) = rect

    widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    maxWidth = max(int(widthA), int(widthB))

    heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    maxHeight = max(int(heightA), int(heightB))

    dst = np.array([
        [0, 0],
        [maxWidth - 1, 0],
        [maxWidth - 1, maxHeight - 1],
        [0, maxHeight - 1]
    ], dtype="float32")

    M = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
    return warped

def detect_page_contour(image: np.ndarray) -> np.ndarray:
    """Locates page boundary quadrilateral contour."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edged = cv2.Canny(blurred, 75, 200)

    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]

    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4:
            return approx.reshape(4, 2)

    # Fallback to full image bounds if no quad contour found
    h, w = gray.shape[:2]
    return np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype="float32")

def visualize_segmentation(original: np.ndarray, warped: np.ndarray, binary: np.ndarray, cell_patches: List[np.ndarray], max_cells_display: int = 16, save_path: str = None):
    """
    Visualizes preprocessing stages and a sample grid of extracted Braille cells using Matplotlib.
    """
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 2, figsize=(10, 8))
    
    # Original image
    if len(original.shape) == 3:
        axes[0, 0].imshow(cv2.cvtColor(original, cv2.COLOR_BGR2RGB))
    else:
        axes[0, 0].imshow(original, cmap='gray')
    axes[0, 0].set_title("1. Original Image")
    axes[0, 0].axis('off')

    # Perspective corrected image
    if len(warped.shape) == 3:
        axes[0, 1].imshow(cv2.cvtColor(warped, cv2.COLOR_BGR2RGB))
    else:
        axes[0, 1].imshow(warped, cmap='gray')
    axes[0, 1].set_title("2. Perspective Corrected")
    axes[0, 1].axis('off')

    # Adaptive Thresholded Binary image
    axes[1, 0].imshow(binary, cmap='gray')
    axes[1, 0].set_title("3. CLAHE + Adaptive Thresholding")
    axes[1, 0].axis('off')

    # Grid sample of extracted 28x28 Braille cells
    n_show = min(len(cell_patches), max_cells_display)
    if n_show > 0:
        grid_cols = int(np.ceil(np.sqrt(n_show)))
        grid_rows = int(np.ceil(n_show / grid_cols))
        cell_grid = np.zeros((grid_rows * 28, grid_cols * 28), dtype=np.uint8)
        for idx in range(n_show):
            r = idx // grid_cols
            c = idx % grid_cols
            cell_grid[r*28:(r+1)*28, c*28:(c+1)*28] = cell_patches[idx]
        axes[1, 1].imshow(cell_grid, cmap='gray')
        axes[1, 1].set_title(f"4. Segmented Braille Cells ({len(cell_patches)} Total)")
    else:
        axes[1, 1].set_title("4. No Cells Extracted")
    axes[1, 1].axis('off')

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, bbox_inches='tight', dpi=150)
        print(f"Visualization saved to {save_path}")
    plt.close()

def preprocess_braille_image(image_path: str) -> Tuple[np.ndarray, List[np.ndarray]]:
    """
    Executes complete OpenCV pipeline:
    1. Loads image.
    2. Detects page boundary quad and warps perspective.
    3. Enhances contrast via CLAHE & adaptive thresholding.
    4. Segments page into individual 28x28 6-dot cell patches.
    """
    image = cv2.imread(image_path)
    if image is None:
        raise FileNotFoundError(f"Image not found at path: {image_path}")

    # Page detection and perspective correction
    page_pts = detect_page_contour(image)
    warped = four_point_transform(image, page_pts)
    gray = cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY) if len(warped.shape) == 3 else warped

    # Contrast enhancement & noise reduction (CLAHE + Gaussian Blur)
    blurred = cv2.GaussianBlur(gray, (3, 3), 0)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(blurred)
    binary = cv2.adaptiveThreshold(
        enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 11, 2
    )

    # Projection profile cell grid segmentation
    cell_patches = []
    h, w = binary.shape
    cell_w, cell_h = max(10, w // 20), max(10, h // 10)  # Standard grid split heuristic

    for row in range(0, h - cell_h + 1, cell_h):
        for col in range(0, w - cell_w + 1, cell_w):
            cell = binary[row:row+cell_h, col:col+cell_w]
            resized_cell = cv2.resize(cell, (28, 28), interpolation=cv2.INTER_AREA)
            cell_patches.append(resized_cell)

    return binary, cell_patches


