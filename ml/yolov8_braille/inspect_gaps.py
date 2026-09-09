import numpy as np
from PIL import Image
import tensorflow as tf
from test_cleaned_output import get_complete_braille_map, nms

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
print(f"med_w: {med_w:.2f}, med_h: {med_h:.2f}")
all_gaps = []
for idx, l in enumerate(lines):
    print(f"\n--- Line {idx} ({len(l)} chars) ---")
    last_x2 = -1
    line_str = []
    for d in l:
        char = bmap.get(f"{d['cls']:06b}", '?')
        line_str.append(char)
        if last_x2 > 0:
            gap = d['x1'] - last_x2
            all_gaps.append(gap)
            ratio = gap / med_w
            print(f"  -> '{char}' w={d['w']:.1f}, gap={gap:.2f} (gap/med_w = {ratio:.2f})")
        else:
            print(f"  First '{char}' w={d['w']:.1f}")
        last_x2 = d['x2']
    print(f"Chars: {''.join(line_str)}")

all_gaps = np.array(all_gaps)
print(f"\nGaps summary: min={all_gaps.min():.2f}, 25%={np.percentile(all_gaps, 25):.2f}, 50%={np.median(all_gaps):.2f}, 75%={np.percentile(all_gaps, 75):.2f}, max={all_gaps.max():.2f}")
