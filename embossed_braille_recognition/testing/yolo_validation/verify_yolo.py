import os
import sys
import numpy as np
from PIL import Image
import tensorflow as tf

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from ml.braille_ocr import louis

def nms(boxes, scores, iou_threshold=0.45):
    if len(boxes) == 0:
        return []
    x1 = boxes[:, 0]
    y1 = boxes[:, 1]
    x2 = boxes[:, 2]
    y2 = boxes[:, 3]
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

def verify(tflite_path="ml/yolov8_braille/yolov8_braille.tflite", img_path="AngelinaReader/DSBI/data/Fundamentals of Massage/FM+1+recto.jpg"):
    print("Testing YOLOv8 Braille TFLite Inference on:", img_path)
    if not os.path.exists(img_path):
        print(f"Sample image not found: {img_path}")
        return
    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    img = Image.open(img_path).convert('RGB')
    resized = img.resize((640, 640))
    arr = np.array(resized, dtype=np.float32) / 255.0
    arr = np.expand_dims(arr, axis=0) # [1, 640, 640, 3]

    interpreter.set_tensor(input_details[0]['index'], arr)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]['index'])[0] # shape [68, 8400]

    predictions = output.T

    boxes = []
    scores = []
    class_indices = []

    conf_thresh = 0.25
    for i in range(8400):
        row = predictions[i]
        cx, cy, w, h = row[:4]
        class_probs = row[4:]
        cls_idx = np.argmax(class_probs)
        cls_conf = class_probs[cls_idx]

        if cls_conf > conf_thresh and cls_idx > 0:
            x1 = cx - w / 2.0
            y1 = cy - h / 2.0
            x2 = cx + w / 2.0
            y2 = cy + h / 2.0
            boxes.append([x1, y1, x2, y2])
            scores.append(cls_conf)
            class_indices.append(cls_idx)

    boxes = np.array(boxes)
    scores = np.array(scores)
    class_indices = np.array(class_indices)

    print(f"Candidate detections above {conf_thresh*100:.0f}% confidence: {len(boxes)}")
    if len(boxes) == 0:
        print("No Braille characters detected.")
        return

    keep = nms(boxes, scores, iou_threshold=0.45)
    keep_boxes = boxes[keep]
    keep_scores = scores[keep]
    keep_classes = class_indices[keep]
    print(f"Detections after NMS: {len(keep_boxes)}")

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
    line_y = -1

    for d in detections:
        if line_y < 0:
            current_line.append(d)
            line_y = d['cy']
        elif abs(d['cy'] - line_y) < (median_h * 0.7):
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

    full_text = []
    for line in lines:
        line_chars = []
        last_x = -1
        for d in line:
            if last_x > 0 and (d['cx'] - last_x) > (median_w * 1.6):
                if line_chars and line_chars[-1] != ' ':
                    line_chars.append(' ')
            last_x = d['cx']

            bin_str = f"{d['class']:06b}"
            d1, d2, d3, d4, d5, d6 = [int(ch) for ch in bin_str]
            mask = d1 | (d2 << 1) | (d3 << 2) | (d4 << 3) | (d5 << 4) | (d6 << 5)
            if mask == 0:
                if line_chars and line_chars[-1] != ' ':
                    line_chars.append(' ')
            else:
                line_chars.append(chr(0x2800 + mask))
        raw_u = "".join(line_chars).strip()
        if raw_u:
            eng = louis.backTranslateString(['en-ueb-g2.ctb'], raw_u)
            full_text.append(eng)

    result_text = "\n".join(full_text)
    print("\n" + "="*50)
    print("RECOGNIZED TEXT FROM YOLO (LIBLOUIS BACK-TRANSLATION):")
    print("="*50)
    print(result_text[:400])
    print("="*50)

if __name__ == '__main__':
    verify()
