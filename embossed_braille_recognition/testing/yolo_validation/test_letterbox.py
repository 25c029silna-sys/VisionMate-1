import numpy as np
from PIL import Image
import tensorflow as tf
from test_cleaned_output import nms
import re

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

for mode in ['squished', 'letterbox']:
    orig = Image.open('ml/yolov8_braille/captured_phone.jpg').convert('RGB').rotate(270, expand=True)
    if mode == 'squished':
        img = orig.resize((640, 640))
    else:
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
        min_conf = 0.48 if c in punct_classes else 0.30
        if conf >= min_conf and c > 0:
            cx, cy, w, h = r_det[:4]
            boxes.append([cx - w/2, cy - h/2, cx + w/2, cy + h/2])
            scores.append(conf)
            classes.append(c)

    boxes = np.array(boxes)
    scores = np.array(scores)
    classes = np.array(classes)
    keep = nms(boxes, scores, 0.40)
    print(f"[{mode.upper()}] Detections after NMS: {len(keep)}")
    if len(keep) > 0:
        med_w = np.median(boxes[keep, 2] - boxes[keep, 0])
        med_h = np.median(boxes[keep, 3] - boxes[keep, 1])
        print(f"[{mode.upper()}] Aspect ratio of cells (h/w): {med_h/med_w:.2f} (w={med_w:.1f}, h={med_h:.1f})")
