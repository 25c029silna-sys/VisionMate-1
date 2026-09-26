import os
import argparse
from PIL import Image

def parse_dsbi_annotation(txt_path):
    """
    Parses a DSBI annotation .txt file.
    Returns a list of tuples: (left, top, right, bottom, class_idx)
    """
    with open(txt_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
        if len(lines) < 4:
            return []

        v_lines = list(map(int, lines[1].split()))
        h_lines = list(map(int, lines[2].split()))

        cells = []
        for line in lines[3:]:
            parts = line.split()
            if len(parts) != 8:
                continue
            row = int(parts[0])
            col = int(parts[1])
            binary_str = ''.join(parts[2:])

            left = v_lines[(col - 1) * 2]
            right = v_lines[(col - 1) * 2 + 1]
            top = h_lines[(row - 1) * 3]
            bottom = h_lines[(row - 1) * 3 + 2]

            class_idx = int(binary_str, 2)
            cells.append((left, top, right, bottom, class_idx))

        return cells

def process_dsbi_folder(dsbi_dir, output_dir):
    """
    Recursively processes all DSBI image and .txt pairs, crops cell patches,
    resizes to 28x28 grayscale, and saves into ml/braille_cnn/data/<class_idx>/.
    """
    os.makedirs(output_dir, exist_ok=True)
    for c in range(64):
        os.makedirs(os.path.join(output_dir, str(c)), exist_ok=True)

    image_paths = []
    for root, dirs, files in os.walk(dsbi_dir):
        for f in files:
            if f.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp')):
                image_paths.append(os.path.join(root, f))

    print(f"Found {len(image_paths)} DSBI images across subdirectories in '{dsbi_dir}'...")

    extracted_count = 0
    for img_path in image_paths:
        base_path = os.path.splitext(img_path)[0]
        txt_path = f"{base_path}.txt"
        if not os.path.exists(txt_path):
            continue

        base_name = os.path.basename(base_path)
        try:
            with Image.open(img_path) as img:
                img_gray = img.convert('L')
                cells = parse_dsbi_annotation(txt_path)
                w, h = img_gray.size

                for idx, (left, top, right, bottom, class_idx) in enumerate(cells):
                    # Clamp bounding box coordinates
                    left_c = max(0, min(w - 1, left))
                    top_c = max(0, min(h - 1, top))
                    right_c = max(left_c + 1, min(w, right))
                    bottom_c = max(top_c + 1, min(h, bottom))

                    crop = img_gray.crop((left_c, top_c, right_c, bottom_c))
                    resized_crop = crop.resize((28, 28), Image.Resampling.BILINEAR)

                    out_path = os.path.join(output_dir, str(class_idx), f"{base_name}_cell_{idx:04d}.png")
                    resized_crop.save(out_path)
                    extracted_count += 1
        except Exception as e:
            print(f"Error processing {img_path}: {e}")

    print(f"Successfully extracted {extracted_count} Braille cell patches into '{output_dir}'.")

def main():
    parser = argparse.ArgumentParser(description="Prepare DSBI/AngelinaReader dataset")
    parser.add_argument("--dsbi_dir", type=str, required=True, help="Path to unzipped DSBI dataset directory containing .jpg and .txt files")
    parser.add_argument("--output_dir", type=str, default="ml/braille_cnn/data", help="Output directory")
    args = parser.parse_args()

    process_dsbi_folder(args.dsbi_dir, args.output_dir)

if __name__ == '__main__':
    main()
