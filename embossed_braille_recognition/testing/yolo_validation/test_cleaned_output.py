import sys
import os
import io

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from ml.braille_ocr import louis

import numpy as np
from PIL import Image
import tensorflow as tf
import re

def nms(boxes, scores, iou_threshold=0.40):
    if len(boxes) == 0:
        return []
    x1, y1, x2, y2 = boxes[:, 0], boxes[:, 1], boxes[:, 2], boxes[:, 3]
    areas = (x2 - x1) * (y2 - y1)
    order = scores.argsort()[::-1]
    keep = []
    while order.size > 0:
        i = order[0]
        keep.append(i)
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        w = np.maximum(0.0, xx2 - xx1)
        h = np.maximum(0.0, yy2 - yy1)
        inter = w * h
        ovr = inter / (areas[i] + areas[order[1:]] - inter + 1e-6)
        inds = np.where(ovr <= iou_threshold)[0]
        order = order[inds + 1]
    return keep

def run_cleaned():
    interp = tf.lite.Interpreter('app/assets/models/yolov8_braille.tflite')
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]['index']
    out = interp.get_output_details()[0]['index']

    orig = Image.open('ml/yolov8_braille/captured_phone.jpg').convert('RGB')
    img = orig.rotate(270, expand=True).resize((640, 640))
    arr = np.expand_dims(np.array(img, dtype=np.float32) / 255.0, axis=0)
    interp.set_tensor(inp, arr)
    interp.invoke()
    preds = interp.get_tensor(out)[0].T

    # Punctuation & sparse classes easily triggered by faint shadows
    punct_classes = {1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 24, 25, 26}

    boxes, scores, classes = [], [], []
    for r in preds:
        probs = r[4:]
        c = int(np.argmax(probs))
        conf = float(probs[c])

        # Require 0.48 confidence for punctuation/sparse classes, 0.30 for letters
        min_conf = 0.48 if c in punct_classes else 0.30

        if conf >= min_conf and c > 0:
            cx, cy, w, h = r[:4]
            boxes.append([cx - w/2, cy - h/2, cx + w/2, cy + h/2])
            scores.append(conf)
            classes.append(c)

    boxes = np.array(boxes)
    scores = np.array(scores)
    classes = np.array(classes)

    keep = nms(boxes, scores, 0.40)
    boxes = boxes[keep]
    scores = scores[keep]
    classes = classes[keep]

    med_w = np.median(boxes[:, 2] - boxes[:, 0])
    med_h = np.median(boxes[:, 3] - boxes[:, 1])

    dets = []
    for i, b in enumerate(boxes):
        dets.append({
            'x1': b[0], 'y1': b[1], 'x2': b[2], 'y2': b[3],
            'cx': (b[0] + b[2]) / 2, 'cy': (b[1] + b[3]) / 2,
            'cls': classes[i], 'conf': scores[i]
        })

    dets.sort(key=lambda d: d['cy'])

    lines = []
    curr = []
    line_y = -1.0
    for d in dets:
        if line_y < 0:
            curr.append(d)
            line_y = d['cy']
        elif abs(d['cy'] - line_y) < med_h * 0.70:
            curr.append(d)
            line_y = np.mean([x['cy'] for x in curr])
        else:
            curr.sort(key=lambda x: x['cx'])
            lines.append(curr)
            curr = [d]
            line_y = d['cy']
    if curr:
        curr.sort(key=lambda x: x['cx'])
        lines.append(curr)

    unicode_lines = []
    translated_lines = []

    for l in lines:
        chars = []
        last_x2 = -1.0
        for d in l:
            # Space threshold: insert space if gap > 0.8 * character width
            if last_x2 > 0 and (d['x1'] - last_x2) > (med_w * 0.80):
                if chars and chars[-1] != ' ':
                    chars.append(' ')
            last_x2 = d['x2']

            bin_str = f"{d['cls']:06b}"
            d1 = int(bin_str[0])
            d2 = int(bin_str[1])
            d3 = int(bin_str[2])
            d4 = int(bin_str[3])
            d5 = int(bin_str[4])
            d6 = int(bin_str[5])

            # 1. Cell-to-Unicode Mapping:
            # 0x2800 + (d1 | (d2 << 1) | (d3 << 2) | (d4 << 3) | (d5 << 4) | (d6 << 5))
            # Empty cells (where sum of dots == 0) mapped strictly to a literal space ' '
            mask = d1 | (d2 << 1) | (d3 << 2) | (d4 << 3) | (d5 << 4) | (d6 << 5)
            if mask == 0:
                if chars and chars[-1] != ' ':
                    chars.append(' ')
            else:
                chars.append(chr(0x2800 + mask))

        unicode_line_str = "".join(chars).strip()
        if not unicode_line_str:
            continue

        # 2. One-Pass Back-Translation:
        # Pass that string directly into:
        #     louis.backTranslateString(['en-ueb-g2.ctb'], unicode_line_str)
        # Do NOT run any intermediate character substitutions or lookup dictionaries before or after this call.
        english_line = louis.backTranslateString(['en-ueb-g2.ctb'], unicode_line_str)
        unicode_lines.append(unicode_line_str)
        translated_lines.append(english_line)

    print("\n" + "=" * 80)
    print("RAW UNICODE BRAILLE AND ONE-PASS LIBLOUIS TRANSLATED ENGLISH:")
    print("=" * 80)
    for i, (u_str, eng) in enumerate(zip(unicode_lines, translated_lines)):
        print(f"Line {i:02d} | Braille: {u_str} | English: {eng}")

    print("\n" + "=" * 80)
    print("VERIFICATION OF TARGET LINES (LINE 7 & LINE 15):")
    print("=" * 80)
    if len(unicode_lines) > 7:
        print(f"Line  7 | Braille: {unicode_lines[7]} | English: {translated_lines[7]}")
    if len(unicode_lines) > 15:
        print(f"Line 15 | Braille: {unicode_lines[15]} | English: {translated_lines[15]}")
    print("=" * 80)

if __name__ == '__main__':
    run_cleaned()
