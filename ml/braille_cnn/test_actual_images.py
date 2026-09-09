import os
import random
import numpy as np
from PIL import Image
import tensorflow as tf

def load_labels(labels_path="app/assets/labels/braille_labels.txt"):
    if os.path.exists(labels_path):
        with open(labels_path, 'r', encoding='utf-8') as f:
            lines = [line.replace('\r', '').replace('\n', '') for line in f]
            if lines and lines[0] == '':
                lines[0] = ' '
            return lines
    return [str(i) for i in range(64)]

def parse_dsbi_annotation(txt_path):
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
            cells.append((row, col, left, top, right, bottom, class_idx))
        return cells

def run_tflite_inference(interpreter, input_index, output_index, img_pil):
    resized = img_pil.convert('L').resize((28, 28))
    arr = np.array(resized, dtype=np.float32).reshape(1, 28, 28, 1)
    interpreter.set_tensor(input_index, arr)
    interpreter.invoke()
    probs = interpreter.get_tensor(output_index)[0]
    pred_class = int(np.argmax(probs))
    confidence = float(probs[pred_class])
    return pred_class, confidence

def test_random_actual_patches(model_path="app/assets/models/braille_cnn.tflite", data_dir="ml/braille_cnn/data", num_samples=25):
    labels = load_labels()
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    input_index = interpreter.get_input_details()[0]['index']
    output_index = interpreter.get_output_details()[0]['index']

    print("=" * 80)
    print(" TEST 1: INFERENCE ON 25 REAL PHOTOGRAPHED BRAILLE CELL IMAGES")
    print("=" * 80)
    print(f"{'Sample #':<10} {'Image Filename':<32} {'True Char':<10} {'Pred Char':<10} {'Confidence':<12} {'Status'}")
    print("-" * 80)

    # Pick 25 diverse classes representing key letters & symbols
    test_classes = [32, 48, 36, 38, 34, 52, 54, 50, 20, 22, 40, 56, 44, 46, 42, 60, 62, 58, 28, 30, 41, 57, 23, 45, 47]
    correct = 0

    for i, c in enumerate(test_classes):
        folder = os.path.join(data_dir, str(c))
        if not os.path.exists(folder):
            continue
        files = [f for f in os.listdir(folder) if f.lower().endswith(('.png', '.jpg'))]
        if not files:
            continue
        # Select an image from the end of the folder to test hold-out real photographs
        chosen_file = files[-1 - (i % 5)]
        img_path = os.path.join(folder, chosen_file)

        img = Image.open(img_path)
        pred_class, conf = run_tflite_inference(interpreter, input_index, output_index, img)

        true_char = labels[c] if c < len(labels) else str(c)
        pred_char = labels[pred_class] if pred_class < len(labels) else str(pred_class)

        is_match = (pred_class == c)
        if is_match:
            correct += 1
        status = "[PASS]" if is_match else "[FAIL]"

        display_name = chosen_file[:30]
        print(f"#{i+1:<9} {display_name:<32} '{true_char}' (c={c:<2})  '{pred_char}' (c={pred_class:<2})  {conf*100:6.1f}%       {status}")

    acc = correct / len(test_classes) * 100
    print("-" * 80)
    print(f"Result: {correct}/{len(test_classes)} Correct ({acc:.1f}% Accuracy on actual Braille photos)\n")

def test_full_photographed_document_page(model_path="app/assets/models/braille_cnn.tflite",
                                        img_path="AngelinaReader/DSBI/data/Fundamentals of Massage/FM+1+recto.jpg",
                                        txt_path="AngelinaReader/DSBI/data/Fundamentals of Massage/FM+1+recto.txt"):
    if not os.path.exists(img_path) or not os.path.exists(txt_path):
        print(f"Full page photo '{img_path}' not found, skipping full page test.")
        return

    labels = load_labels()
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    input_index = interpreter.get_input_details()[0]['index']
    output_index = interpreter.get_output_details()[0]['index']

    page_img = Image.open(img_path).convert('L')
    cells = parse_dsbi_annotation(txt_path)

    print("=" * 80)
    print(f" TEST 2: FULL REAL BOOK PAGE RECOGNITION")
    print(f" Document Photo: {img_path}")
    print(f" Photo Dimensions: {page_img.size[0]}x{page_img.size[1]} pixels")
    print(f" Total Annotated Braille Cells: {len(cells)}")
    print("=" * 80)

    correct_cells = 0
    total_cells = len(cells)

    ground_truth_text = []
    recognized_text = []
    last_row = -1

    for row, col, left, top, right, bottom, true_class in cells:
        w, h = page_img.size
        # Clamp bounds
        l = max(0, min(w - 1, left))
        r = max(0, min(w, right))
        t = max(0, min(h - 1, top))
        b = max(0, min(h, bottom))

        if r <= l or b <= t:
            continue

        patch = page_img.crop((l, t, r, b))
        pred_class, conf = run_tflite_inference(interpreter, input_index, output_index, patch)

        if pred_class == true_class:
            correct_cells += 1

        if row != last_row and last_row != -1:
            ground_truth_text.append('\n')
            recognized_text.append('\n')
        last_row = row

        t_char = labels[true_class] if true_class < len(labels) else '?'
        p_char = labels[pred_class] if pred_class < len(labels) else '?'
        ground_truth_text.append(t_char)
        recognized_text.append(p_char)

    page_acc = (correct_cells / total_cells * 100) if total_cells > 0 else 0

    print(f"\n--- Full Page Recognition Results ---")
    print(f" Correctly Recognized Cells:  {correct_cells} / {total_cells}")
    print(f" Overall Page Accuracy:       {page_acc:.2f}%\n")

    gt_str = "".join(ground_truth_text).strip()
    rec_str = "".join(recognized_text).strip()

    print("Ground Truth Transcription Sample (First 150 chars):")
    print(repr(gt_str[:150]))
    print("\nModel Recognized Transcription Sample (First 150 chars):")
    print(repr(rec_str[:150]))
    print("=" * 80)

if __name__ == '__main__':
    test_random_actual_patches()
    test_full_photographed_document_page()
