import numpy as np
from PIL import Image
import tensorflow as tf
import re

def get_complete_braille_map():
    return {
        '000000': ' ',
        '000001': ',',
        '000010': '',
        '000011': ';',
        '000100': '',
        '000101': '/',
        '000110': '',
        '000111': '?',
        '001000': '\'',
        '001001': '-',
        '001010': '*',
        '001011': '.',
        '001100': '"',
        '001101': '_',
        '001110': '',
        '001111': '#',
        '010000': ';',
        '010001': ',',
        '010010': ':',
        '010011': '.',
        '010100': 'i',
        '010101': 'en',
        '010110': 'j',
        '010111': 'w',
        '011000': ';',
        '011001': '?',
        '011010': '!',
        '011011': '(',
        '011100': 's',
        '011101': 'the',
        '011110': 't',
        '011111': 'with',
        '100000': 'a',
        '100001': 'ch',
        '100010': 'e',
        '100011': 'sh',
        '100100': 'c',
        '100101': 'wh',
        '100110': 'd',
        '100111': 'th',
        '101000': 'k',
        '101001': 'u',
        '101010': 'o',
        '101011': 'z',
        '101100': 'm',
        '101101': 'x',
        '101110': 'n',
        '101111': 'y',
        '110000': 'b',
        '110001': 'gh',
        '110010': 'h',
        '110011': 'ou',
        '110100': 'f',
        '110101': 'ed',
        '110110': 'g',
        '110111': 'er',
        '111000': 'l',
        '111001': 'v',
        '111010': 'r',
        '111011': 'for',
        '111100': 'p',
        '111101': 'and',
        '111110': 'q',
        '111111': 'of'
    }

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

    bmap = get_complete_braille_map()
    clean_lines = []

    for l in lines:
        chars = []
        last_x2 = -1.0
        for d in l:
            # Edge-to-edge gap threshold:
            # Only insert space if distance from previous box's right edge to this box's left edge is > 0.8 * character width
            if last_x2 > 0 and (d['x1'] - last_x2) > (med_w * 0.80):
                chars.append(' ')
            last_x2 = d['x2']

            bin_str = f"{d['cls']:06b}"
            raw = bmap.get(bin_str, '')
            chars.append(raw)

        raw_line = "".join(chars)

        # Post-processing filters:
        # 1. Remove isolated punctuation standing alone between spaces: e.g. " ; ", " ' ", " - "
        cleaned = re.sub(r'(?<=\s)[;\',\-\*\.\:\?\!/](?=\s|$)', '', raw_line)
        cleaned = re.sub(r'^[;\',\-\*\.\:\?\!/]\s+', '', cleaned)
        cleaned = re.sub(r'\s+[;\',\-\*\.\:\?\!/]$', '', cleaned)
        # 2. Collapse multiple spaces
        cleaned = re.sub(r'\s{2,}', ' ', cleaned).strip()

        if cleaned:
            clean_lines.append(cleaned)

    print("\n" + "="*60)
    print("CLEANED & FILTERED TEXT:")
    print("="*60)
    print("\n".join(clean_lines))
    print("="*60)

if __name__ == '__main__':
    run_cleaned()
