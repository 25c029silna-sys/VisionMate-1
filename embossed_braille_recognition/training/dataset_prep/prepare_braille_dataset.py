import os
import argparse
import random
import math
from PIL import Image, ImageDraw, ImageFilter

def generate_braille_cell(class_idx: int, img_size: int = 28) -> Image.Image:
    """
    Generates a realistic 28x28 grayscale image of a 6-dot Braille cell for class index 0..63.
    class_idx binary representation maps to dot states [d1, d2, d3, d4, d5, d6].
    """
    bg_val = random.randint(180, 230)
    img = Image.new('L', (img_size, img_size), bg_val)
    draw = ImageDraw.Draw(img)

    # 6-dot cell coordinates (2 columns x 3 rows) in 28x28
    dot_coords = [
        (8, 5),   # Dot 1
        (8, 14),  # Dot 2
        (8, 23),  # Dot 3
        (20, 5),  # Dot 4
        (20, 14), # Dot 5
        (20, 23)  # Dot 6
    ]

    binary_str = format(class_idx, '06b')

    for k in range(6):
        is_active = (binary_str[k] == '1')
        base_x, base_y = dot_coords[k]

        x = base_x + random.randint(-1, 1)
        y = base_y + random.randint(-1, 1)
        r = random.randint(2, 3)

        if is_active:
            shadow_val = max(30, bg_val - random.randint(70, 120))
            draw.ellipse([x - r, y - r, x + r, y + r], fill=shadow_val)
            hl_val = min(255, bg_val + random.randint(30, 60))
            draw.ellipse([x - 1, y - 1, x, y], fill=hl_val)

    # Slight rotation (-5 to +5 degrees)
    angle = random.uniform(-5.0, 5.0)
    img = img.rotate(angle, resample=Image.Resampling.BILINEAR, fillcolor=bg_val)

    if random.random() < 0.4:
        img = img.filter(ImageFilter.GaussianBlur(radius=0.5))

    return img

def main():
    parser = argparse.ArgumentParser(description="Generate synthetic Braille cell dataset")
    parser.add_argument("--output_dir", type=str, default="ml/braille_cnn/data", help="Output directory")
    parser.add_argument("--samples_per_class", type=int, default=150, help="Number of images per class (0..63)")
    args = parser.parse_args()

    output_dir = args.output_dir
    os.makedirs(output_dir, exist_ok=True)

    print(f"Generating {args.samples_per_class} Braille cell images for each of the 64 classes into '{output_dir}'...")

    total_generated = 0
    for class_idx in range(64):
        class_folder = os.path.join(output_dir, str(class_idx))
        os.makedirs(class_folder, exist_ok=True)

        for s in range(args.samples_per_class):
            cell_img = generate_braille_cell(class_idx)
            file_path = os.path.join(class_folder, f"cell_{class_idx}_{s:04d}.png")
            cell_img.save(file_path)
            total_generated += 1

    print(f"Dataset preparation complete! Total images generated: {total_generated} across 64 classes in '{output_dir}'.")

if __name__ == '__main__':
    main()

