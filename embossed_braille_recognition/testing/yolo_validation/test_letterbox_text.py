import sys
import os
import re
import numpy as np
from PIL import Image
import tensorflow as tf

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from ml.braille_ocr import louis
from test_cleaned_output import nms

def letterbox(im, new_shape=(640, 640), color=(114, 114, 114)):
    shape = im.size # (w, h)
    r = min(new_shape[0] / shape[0], new_shape[1] / shape[1])
    new_unpad = (int(round(shape[0] * r)), int(round(shape[1] * r)))
    dw, dh = new_shape[0] - new_unpad[0], new_shape[1] - new_unpad[1]
    dw /= 2
    dh /= 2

    if shape != new_unpad:
        im = im.resize(new_unpad, Image.BILINEAR)
    top, bottom = int(round(dh - 0.1)), int(round(dh + 0.1))
    left, right = int(round(dw - 0.1)), int(round(dw + 0.1))
    
    new_im = Image.new('RGB', new_shape, color)
    new_im.paste(im, (left, top))
    return new_im, r, (left, top)

interp = tf.lite.Interpreter('app/assets/models/yolov8_braille.tflite')
interp.allocate_tensors()
inp = interp.get_input_details()[0]['index']
out = interp.get_output_details()[0]['index']
punct_classes = {1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 24, 25, 26}

for img_name in ['captured_phone.jpg', 'captured_phone_2.jpg']:
    orig = Image.open(f'ml/yolov8_braille/{img_name}').convert('RGB').rotate(270, expand=True)
    img, r, (pad_x, pad_y) = letterbox(orig, (640, 640))
    arr = np.expand_dims(np.array(img, dtype=np.float32) / 255.0, axis=0)
    interp.set_tensor(inp, arr)
    interp.invoke()
    preds = interp.get_tensor(out)[0].T

    boxes, scores, classes = [], [], []
    for r_det in preds:
        probs = r_det[4:]
        c = int(np.argmax(probs))
        conf = float(probs[c])
        min_conf = 0.45 if c in punct_classes else 0.28
        if conf >= min_conf and c > 0:
            cx, cy, w, h = r_det[:4]
            boxes.append([cx - w/2, cy - h/2, cx + w/2, cy + h/2])
            scores.append(conf)
            classes.append(c)

    boxes = np.array(boxes)
    scores = np.array(scores)
    classes = np.array(classes)
    keep = nms(boxes, scores, 0.40)
    boxes = boxes[keep]
    classes = classes[keep]

    med_w = np.median(boxes[:, 2] - boxes[:, 0])
    med_h = np.median(boxes[:, 3] - boxes[:, 1])

    dets = [{'x1': b[0], 'y1': b[1], 'x2': b[2], 'y2': b[3], 'cx': (b[0]+b[2])/2, 'cy': (b[1]+b[3])/2, 'cls': classes[i]} for i, b in enumerate(boxes)]
    dets.sort(key=lambda d: d['cy'])
    lines, curr, line_y = [], [], -1.0
    for d in dets:
        if line_y < 0: curr.append(d); line_y = d['cy']
        elif abs(d['cy'] - line_y) < med_h * 0.70: curr.append(d); line_y = np.mean([x['cy'] for x in curr])
        else: curr.sort(key=lambda x: x['cx']); lines.append(curr); curr = [d]; line_y = d['cy']
    if curr: curr.sort(key=lambda x: x['cx']); lines.append(curr)

    threshold = med_w * 2.3
    clean_lines = []
    for l in lines:
        chars = []
        last_x2 = -1
        for d in l:
            if last_x2 > 0 and (d['x1'] - last_x2) > threshold:
                if chars and chars[-1] != ' ':
                    chars.append(' ')
            last_x2 = d['x2']
            bin_str = f"{d['cls']:06b}"
            d1, d2, d3, d4, d5, d6 = [int(ch) for ch in bin_str]
            mask = d1 | (d2 << 1) | (d3 << 2) | (d4 << 3) | (d5 << 4) | (d6 << 5)
            if mask == 0:
                if chars and chars[-1] != ' ':
                    chars.append(' ')
            else:
                chars.append(chr(0x2800 + mask))
        raw_unicode = "".join(chars).strip()
        if raw_unicode:
            translated = louis.backTranslateString(['en-ueb-g2.ctb'], raw_unicode)
            clean_lines.append(translated)

    print(f"\n================ LETTERBOX DECODED TEXT ({img_name}) ================")
    print("\n".join(clean_lines[:15]))
