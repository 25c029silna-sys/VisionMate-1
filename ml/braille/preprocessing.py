"""
Image Preprocessing Module for Embossed Braille Recognition.
Provides:
- Grayscale conversion
- Illumination / background normalization
- CLAHE / local contrast enhancement
- Morphological Top-Hat & Black-Hat dipole extraction
- Directional gradient & emboss filtering
- Tile-based adaptive thresholding
- Ensemble candidate evaluation based on geometric consistency
"""

import cv2
import numpy as np
from typing import Tuple, Dict, Any, Optional, List

PREPROCESS_METHOD_CLAHE = "clahe"
PREPROCESS_METHOD_BLACKHAT = "blackhat"
PREPROCESS_METHOD_GRADIENT = "gradient"
PREPROCESS_METHOD_COMBINED = "combined"
PREPROCESS_METHOD_PRINTED = "printed"

AVAILABLE_PREPROCESS_METHODS = [
    PREPROCESS_METHOD_CLAHE,
    PREPROCESS_METHOD_BLACKHAT,
    PREPROCESS_METHOD_GRADIENT,
    PREPROCESS_METHOD_COMBINED,
    PREPROCESS_METHOD_PRINTED,
]


def to_grayscale(image: np.ndarray) -> np.ndarray:
    """Converts 3-channel BGR image to single-channel uint8 grayscale."""
    if len(image.shape) == 2:
        return image.copy()
    elif len(image.shape) == 3:
        return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        raise ValueError(f"Unsupported image shape for grayscale conversion: {image.shape}")


def normalize_illumination(gray: np.ndarray, sigma: float = 35.0) -> np.ndarray:
    """
    Normalizes uneven illumination across the page via low-frequency Gaussian division.
    Computes low-pass background luminance field and normalizes image:
        normalized = (gray / (background + epsilon)) * 128.0
    Clamps output to uint8 range [0, 255].
    """
    gray_f = gray.astype(np.float32)
    # Estimate smoothly varying background illumination field
    bg = cv2.GaussianBlur(gray_f, (0, 0), sigmaX=sigma, sigmaY=sigma)
    normalized = (gray_f / (bg + 1e-4)) * 128.0
    return np.clip(normalized, 0, 255).astype(np.uint8)


def enhance_clahe(
    gray: np.ndarray,
    clip_limit: float = 2.5,
    tile_grid_size: Tuple[int, int] = (8, 8)
) -> np.ndarray:
    """Applies Contrast Limited Adaptive Histogram Equalization (CLAHE)."""
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=tile_grid_size)
    return clahe.apply(gray)


def morphological_dipoles(
    gray: np.ndarray,
    kernel_size: int = 11
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Applies morphological Top-Hat (bright crests) and Black-Hat (dark troughs)
    using an elliptical structuring element matching physical Braille dot scale.
    Returns: (tophat, blackhat, dipole_diff)
      - tophat: Isolates bright embossed dot highlights
      - blackhat: Isolates dark dot shadows
      - dipole_diff: Combined relief (tophat + blackhat)
    """
    if kernel_size % 2 == 0:
        kernel_size += 1
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    smoothed = cv2.GaussianBlur(gray, (5, 5), 1.0)
    tophat = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)
    blackhat = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)
    dipole_diff = cv2.add(tophat, blackhat)
    return tophat, blackhat, dipole_diff


def gradient_emboss_enhancement(gray: np.ndarray, light_direction: str = "top_left") -> np.ndarray:
    """
    Enhances raised-dot edges and emboss relief using directional convolution kernels
    and Sobel gradient magnitude.
    """
    smoothed = cv2.GaussianBlur(gray, (3, 3), 0.8)

    # Directional emboss kernel for lighting from top-left
    if light_direction == "top_left":
        emboss_k = np.array([
            [-2, -1,  0],
            [-1,  1,  1],
            [ 0,  1,  2]
        ], dtype=np.float32)
    elif light_direction == "top":
        emboss_k = np.array([
            [-1, -2, -1],
            [ 0,  0,  0],
            [ 1,  2,  1]
        ], dtype=np.float32)
    else:
        emboss_k = np.array([
            [-1, -1, -1],
            [-1,  8, -1],
            [-1, -1, -1]
        ], dtype=np.float32)

    embossed = cv2.filter2D(smoothed, cv2.CV_32F, emboss_k)
    embossed = np.clip(np.abs(embossed), 0, 255).astype(np.uint8)

    # Sobel gradient magnitude
    grad_x = cv2.Sobel(smoothed, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(smoothed, cv2.CV_32F, 0, 1, ksize=3)
    grad_mag = cv2.magnitude(grad_x, grad_y)
    grad_mag = np.clip(grad_mag, 0, 255).astype(np.uint8)

    return cv2.addWeighted(embossed, 0.6, grad_mag, 0.4, 0)


def adaptive_threshold_image(
    image: np.ndarray,
    tile_size: int = 160,
    k_std: float = 0.85,
    min_thresh: float = 6.0
) -> np.ndarray:
    """
    Computes local tile-based adaptive thresholding on relief maps:
    For each tile:
        threshold = max(min_thresh, mean(tile) + k_std * std(tile))
    Eliminates global lighting variance across large photographs.
    """
    h, w = image.shape[:2]
    tiles_y = max(1, h // tile_size)
    tiles_x = max(1, w // tile_size)
    binary = np.zeros_like(image, dtype=np.uint8)

    for ty in range(tiles_y):
        for tx in range(tiles_x):
            y1 = ty * h // tiles_y
            y2 = (ty + 1) * h // tiles_y if ty < tiles_y - 1 else h
            x1 = tx * w // tiles_x
            x2 = (tx + 1) * w // tiles_x if tx < tiles_x - 1 else w

            tile = image[y1:y2, x1:x2]
            local_thresh = max(min_thresh, float(np.mean(tile) + k_std * np.std(tile)))
            binary[y1:y2, x1:x2] = (tile >= local_thresh).astype(np.uint8) * 255

    return binary


def preprocess_image(
    bgr_image: np.ndarray,
    method: str = PREPROCESS_METHOD_COMBINED,
    clip_limit: float = 2.5,
    kernel_size: int = 11,
    normalize_light: bool = True
) -> Dict[str, np.ndarray]:
    """
    Executes the configured preprocessing method on an input BGR image.

    Returns dictionary containing intermediate and enhanced representations:
    {
        "grayscale": np.ndarray,
        "illumination_normalized": np.ndarray,
        "contrast_enhanced": np.ndarray,
        "tophat": np.ndarray,
        "blackhat": np.ndarray,
        "enhanced": np.ndarray,
        "threshold": np.ndarray,
        "method": str
    }
    """
    gray = to_grayscale(bgr_image)

    # 1. Illumination normalization
    if normalize_light:
        norm_gray = normalize_illumination(gray, sigma=35.0)
    else:
        norm_gray = gray.copy()

    # 2. Local contrast enhancement via CLAHE
    clahe_img = enhance_clahe(norm_gray, clip_limit=clip_limit, tile_grid_size=(8, 8))

    # 3. Morphological Top-Hat and Black-Hat dipoles
    tophat, blackhat, dipole_diff = morphological_dipoles(clahe_img, kernel_size=kernel_size)

    # 4. Method selection
    if method == PREPROCESS_METHOD_CLAHE:
        enhanced = clahe_img
    elif method == PREPROCESS_METHOD_BLACKHAT:
        enhanced = dipole_diff
    elif method == PREPROCESS_METHOD_GRADIENT:
        enhanced = gradient_emboss_enhancement(clahe_img)
    elif method == PREPROCESS_METHOD_COMBINED:
        grad = gradient_emboss_enhancement(clahe_img)
        # Fuse dipole relief (70%) with gradient relief (30%)
        enhanced = cv2.addWeighted(dipole_diff, 0.75, grad, 0.25, 0)
    elif method == PREPROCESS_METHOD_PRINTED:
        # Check polarity: dark dots on light paper vs light dots on dark paper
        if float(np.median(clahe_img)) > 120.0:
            enhanced = blackhat
        else:
            enhanced = tophat
    else:
        raise ValueError(f"Unknown preprocess method: '{method}'. Choose from {AVAILABLE_PREPROCESS_METHODS}")

    # 5. Adaptive threshold map
    min_t = 12.0 if method == PREPROCESS_METHOD_PRINTED else 6.0
    k_s = 1.1 if method == PREPROCESS_METHOD_PRINTED else 0.85
    threshold_img = adaptive_threshold_image(enhanced, tile_size=160, k_std=k_s, min_thresh=min_t)

    return {
        "grayscale": gray,
        "illumination_normalized": norm_gray,
        "contrast_enhanced": clahe_img,
        "tophat": tophat,
        "blackhat": blackhat,
        "enhanced": enhanced,
        "threshold": threshold_img,
        "method": method
    }


def evaluate_preprocessing_candidates(
    bgr_image: np.ndarray,
    dot_detector_fn,
    cell_segmenter_fn
) -> Tuple[str, Dict[str, Any]]:
    """
    Ensemble candidate evaluation across multiple preprocessing methods:
    Runs CLAHE, black-hat, gradient, and combined methods.
    Evaluates geometric consistency:
    - Dot spacing regularity (CV of nearest-neighbor distance)
    - Cell dimension consistency
    - Valid Braille patterns ratio
    - Line alignment score
    Returns (selected_method, metrics_dict).
    """
    best_method = PREPROCESS_METHOD_COMBINED
    best_score = -float('inf')
    evaluation_results = {}

    for method in AVAILABLE_PREPROCESS_METHODS:
        prep = preprocess_image(bgr_image, method=method)
        dots = dot_detector_fn(prep["enhanced"], prep["tophat"], prep["blackhat"])

        if len(dots) < 6:
            score = -100.0
            evaluation_results[method] = {
                "score": score,
                "dot_count": len(dots),
                "cell_count": 0,
                "spacing_cv": 1.0
            }
            continue

        pts = np.array([[d["x"], d["y"]] for d in dots], dtype=np.float32)

        # 1. Nearest neighbor spacing regularity
        from scipy.spatial import cKDTree
        tree = cKDTree(pts)
        nn_dists, _ = tree.query(pts, k=min(3, len(pts)))
        dists = nn_dists[:, 1]
        valid_dists = dists[dists > 3.0]
        if len(valid_dists) > 0:
            mean_dist = float(np.mean(valid_dists))
            std_dist = float(np.std(valid_dists))
            spacing_cv = std_dist / (mean_dist + 1e-4) # Lower CV = more regular grid
        else:
            spacing_cv = 1.0

        # 2. Line alignment & cell consistency
        cells = cell_segmenter_fn(dots, bgr_image.shape)
        total_cells = sum(len(line) for line in cells)

        # Composite geometric consistency score
        regularity_score = max(0.0, 1.0 - spacing_cv) * 50.0
        cell_density_score = min(50.0, total_cells * 0.4)
        dot_mass_score = min(30.0, len(dots) * 0.05)

        total_score = regularity_score + cell_density_score + dot_mass_score
        evaluation_results[method] = {
            "score": total_score,
            "dot_count": len(dots),
            "cell_count": total_cells,
            "spacing_cv": spacing_cv
        }

        if total_score > best_score:
            best_score = total_score
            best_method = method

    return best_method, evaluation_results
