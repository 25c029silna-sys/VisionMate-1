import numpy as np
from PIL import Image
import tensorflow as tf
from ml.yolov8_braille.test_transposed import get_complete_braille_map, nms

def auto_orient_and_decode(img_path="ml/yolov8_braille/captured_phone_2.jpg"):
    interp = tf.lite.Interpreter('app/assets/models/yolov8_braille.tflite')
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]['index']
    out = interp.get_output_details()[0]['index']
    orig = Image.open(img_path).convert('RGB')

    best_rot = 0
    best_score = -1.0
    best_preds = None

    for rot in [0, 90, 180, 270]:
        img = orig.rotate(rot, expand=True).resize((640, 640))
        arr = np.expand_dims(np.array(img, dtype=np.float32) / 255.0, axis=0)
        interp.set_tensor(inp, arr)
        interp.invoke()
        preds = interp.get_tensor(out)[0].T

        good = [r for r in preds if np.argmax(r[4:]) > 0 and np.max(r[4:]) > 0.30]
        score = sum([np.max(r[4:]) for r in good])
        print(f"Orientation {rot:3d}° -> score: {score:.1f} (count: {len(good)})")
        if score > best_score:
            best_score = score
            best_rot = rot
            best_preds = preds

    print(f"\nSelected best orientation: {best_rot}° (score: {best_score:.1f})")

    # Now decode best_preds
    boxes, scores, class_indices = [], [], []
    for r in best_preds:
        cx, cy, w, h = r[:4]
        probs = r[4:]
        c = np.argmax(probs)
        conf = probs[c]
        if conf >= 0.30 and c > 0:
            boxes.append([cx - w/2, cy - h/2, cx + w/2, cy + h/2])
            scores.append(conf)
            class_indices.append(c)

    boxes = np.array(boxes)
    scores = np.array(scores)
    class_indices = np.array(class_indices)

    keep = nms(boxes, scores, iou_threshold=0.40)
    keep_boxes = boxes[keep]
    keep_scores = scores[keep]
    keep_classes = class_indices[keep]

    median_h = np.median(keep_boxes[:, 3] - keep_boxes[:, 1])
    median_w = np.median(keep_boxes[:, 2] - keep_boxes[:, 0])

    detections = []
    for i in range(len(keep_boxes)):
        b = keep_boxes[i]
        detections.append({
            'cx': (b[0] + b[2]) / 2.0,
            'cy': (b[1] + b[3]) / 2.0,
            'w': b[2] - b[0],
            'h': b[3] - b[1],
            'class': keep_classes[i],
            'conf': keep_scores[i]
        })

    detections.sort(key=lambda d: d['cy'])

    lines = []
    current_line = []
    line_y = -1.0

    for d in detections:
        if line_y < 0:
            current_line.append(d)
            line_y = d['cy']
        elif abs(d['cy'] - line_y) < (median_h * 0.70):
            current_line.append(d)
            line_y = np.mean([x['cy'] for x in current_line])
        else:
            current_line.sort(key=lambda x: x['cx'])
            lines.append(current_line)
            current_line = [d]
            line_y = d['cy']

    if current_line:
        current_line.sort(key=lambda x: x['cx'])
        lines.append(current_line)

    braille_map = get_complete_braille_map()
    number_map = {
        'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5',
        'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0'
    }

    full_text = []
    for line in lines:
        line_chars = []
        last_x = -1
        is_number = False
        is_capital = False

        for d in line:
            if last_x > 0 and (d['cx'] - last_x) > (median_w * 1.5):
                line_chars.append(' ')
                is_number = False
            last_x = d['cx']

            bin_str = f"{d['class']:06b}"
            raw = braille_map.get(bin_str, '?')

            if raw == '#':
                is_number = True
                continue
            if raw == ',':
                is_capital = True
                continue

            char = raw
            if is_number and raw in number_map:
                char = number_map[raw]
            elif is_capital:
                char = raw.upper()
                is_capital = False

            line_chars.append(char)
        full_text.append("".join(line_chars))

    result = "\n".join(full_text)
    print("\n" + "="*60)
    print("FINAL DECODED TEXT:")
    print("="*60)
    print(result)
    print("="*60)

if __name__ == '__main__':
    auto_orient_and_decode()
