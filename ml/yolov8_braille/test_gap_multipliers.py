import numpy as np
from PIL import Image
import tensorflow as tf
from test_cleaned_output import get_complete_braille_map, nms
import re

interp = tf.lite.Interpreter('app/assets/models/yolov8_braille.tflite')
interp.allocate_tensors()
inp = interp.get_input_details()[0]['index']
out = interp.get_output_details()[0]['index']

orig = Image.open('ml/yolov8_braille/captured_phone_2.jpg').convert('RGB')
img = orig.rotate(270, expand=True).resize((640, 640))
arr = np.expand_dims(np.array(img, dtype=np.float32) / 255.0, axis=0)
interp.set_tensor(inp, arr)
interp.invoke()
preds = interp.get_tensor(out)[0].T

punct_classes = {1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 24, 25, 26}
boxes, scores, classes = [], [], []
for r in preds:
    probs = r[4:]
    c = int(np.argmax(probs))
    conf = float(probs[c])
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
classes = classes[keep]

med_w = np.median(boxes[:, 2] - boxes[:, 0])
med_h = np.median(boxes[:, 3] - boxes[:, 1])

dets = [{'x1': b[0], 'y1': b[1], 'x2': b[2], 'y2': b[3], 'cx': (b[0]+b[2])/2, 'cy': (b[1]+b[3])/2, 'w': b[2]-b[0], 'cls': classes[i]} for i, b in enumerate(boxes)]
dets.sort(key=lambda d: d['cy'])
lines, curr, line_y = [], [], -1.0
for d in dets:
    if line_y < 0: curr.append(d); line_y = d['cy']
    elif abs(d['cy'] - line_y) < med_h * 0.70: curr.append(d); line_y = np.mean([x['cy'] for x in curr])
    else: curr.sort(key=lambda x: x['cx']); lines.append(curr); curr = [d]; line_y = d['cy']
if curr: curr.sort(key=lambda x: x['cx']); lines.append(curr)

bmap = get_complete_braille_map()

for mult in [1.5, 2.0, 2.5, 3.0, 3.5]:
    threshold = med_w * mult
    result_lines = []
    for l in lines:
        chars = []
        last_x2 = -1
        for d in l:
            if last_x2 > 0 and (d['x1'] - last_x2) > threshold:
                chars.append(' ')
            last_x2 = d['x2']
            chars.append(bmap.get(f"{d['cls']:06b}", ''))
        raw = "".join(chars)
        cleaned = re.sub(r'(?<=\s)[;\',\-\*\.\:\?\!/]+(?=\s|$)', '', raw)
        cleaned = re.sub(r'^[;\',\-\*\.\:\?\!/]+\s*', '', cleaned)
        cleaned = re.sub(r'\s*[;\',\-\*\.\:\?\!/]+$', '', cleaned)
        cleaned = re.sub(r'([a-zA-Z0-9])[;:]+([a-zA-Z0-9])', r'\1\2', cleaned)
        cleaned = re.sub(r'\s{2,}', ' ', cleaned).strip()
        if cleaned:
            result_lines.append(cleaned)
    print(f"\n================ MULTIPLIER {mult} (thresh={threshold:.1f}px) ================")
    for rl in result_lines[:10]:
        print(rl)
