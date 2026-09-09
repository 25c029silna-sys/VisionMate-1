import numpy as np
from PIL import Image, ImageOps
import tensorflow as tf

def get_complete_braille_map():
    # Complete 64-character Braille dictionary (Binary: Dot 1, 2, 3, 4, 5, 6)
    return {
        '000000': ' ',
        '000001': ',',       # Capital sign / comma
        '000010': '',        # Accent
        '000011': ';',
        '000100': '',        # Accent
        '000101': '/',
        '000110': '',
        '000111': '?',
        '001000': '\'',      # Apostrophe
        '001001': '-',       # Hyphen
        '001010': '*',       # Asterisk
        '001011': '.',
        '001100': '"',       # Quotation
        '001101': '_',
        '001110': '',
        '001111': '#',       # Number sign
        '010000': ';',
        '010001': ',',
        '010010': ':',       # Colon
        '010011': '.',       # Period
        '010100': 'i',
        '010101': 'en',
        '010110': 'j',
        '010111': 'w',
        '011000': ';',
        '011001': '?',
        '011010': '!',       # Exclamation
        '011011': '(',       # Parenthesis
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

def test_transposed(img_path="ml/yolov8_braille/captured_phone.jpg", conf_thresh=0.35):
    img = Image.open(img_path)
    # Apply EXIF transpose so portrait photo is right-side up
    img = ImageOps.exif_transpose(img)
    print("Image size after EXIF orientation:", img.size)

    interpreter = tf.lite.Interpreter("app/assets/models/yolov8_braille.tflite")
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    resized = img.convert('RGB').resize((640, 640))
    arr = np.array(resized, dtype=np.float32) / 255.0
    arr = np.expand_dims(arr, axis=0)

    interpreter.set_tensor(input_details[0]['index'], arr)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]['index'])[0] # [68, 8400]
    predictions = output.T

    boxes = []
    scores = []
    class_indices = []

    for i in range(8400):
        row = predictions[i]
        cx, cy, w, h = row[:4]
        class_probs = row[4:]
        cls_idx = np.argmax(class_probs)
        cls_conf = class_probs[cls_idx]

        if cls_conf >= conf_thresh and cls_idx > 0:
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

    print(f"Candidate detections >= {conf_thresh*100:.0f}% conf: {len(boxes)}")
    if len(boxes) == 0:
        print("No Braille characters detected.")
        return

    keep = nms(boxes, scores, iou_threshold=0.40)
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
    print("DECODED TEXT (WITH AUTO-ORIENTATION & COMPLETE MAP):")
    print("="*60)
    print(result)
    print("="*60)

if __name__ == '__main__':
    test_transposed()
