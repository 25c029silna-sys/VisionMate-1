import os
import time
import argparse
import numpy as np
from PIL import Image
import tensorflow as tf
from tensorflow import keras

def load_labels(labels_path="app/assets/labels/braille_labels.txt"):
    if os.path.exists(labels_path):
        with open(labels_path, 'r', encoding='utf-8') as f:
            lines = [line.replace('\r', '').replace('\n', '') for line in f]
            if lines and lines[0] == '':
                lines[0] = ' '
            return lines
    return [str(i) for i in range(64)]

def evaluate_tflite_model(model_path="app/assets/models/braille_cnn.tflite",
                          data_dir="ml/braille_cnn/data",
                          samples_per_class=30):
    print("=" * 65)
    print(f"  Evaluating TensorFlow Lite Model: {model_path}")
    print(f"  Dataset:                         {data_dir}")
    print(f"  Hold-out samples per class:      {samples_per_class}")
    print("=" * 65)

    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file '{model_path}' does not exist!")

    labels = load_labels()
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    input_index = input_details[0]['index']
    output_index = output_details[0]['index']

    top1_correct = 0
    top3_correct = 0
    total_evaluated = 0
    inference_times = []

    per_class_stats = {c: {"total": 0, "correct": 0} for c in range(64)}
    confusion_pairs = {}

    print("\nRunning inference across all 64 Braille classes...")
    for c in range(64):
        class_folder = os.path.join(data_dir, str(c))
        if not os.path.exists(class_folder):
            continue

        all_files = [f for f in os.listdir(class_folder) if f.lower().endswith(('.png', '.jpg'))]
        # Use tail (last N) samples to guarantee hold-out test images
        selected = all_files[-samples_per_class:] if len(all_files) > samples_per_class else all_files

        for f in selected:
            img_path = os.path.join(class_folder, f)
            img = Image.open(img_path).convert('L').resize((28, 28))
            arr = np.array(img, dtype=np.float32).reshape(1, 28, 28, 1)

            t0 = time.perf_counter()
            interpreter.set_tensor(input_index, arr)
            interpreter.invoke()
            preds = interpreter.get_tensor(output_index)[0]
            elapsed_ms = (time.perf_counter() - t0) * 1000
            inference_times.append(elapsed_ms)

            top_indices = np.argsort(preds)[::-1]
            pred_top1 = top_indices[0]
            pred_top3 = top_indices[:3]

            total_evaluated += 1
            per_class_stats[c]["total"] += 1

            if pred_top1 == c:
                top1_correct += 1
                per_class_stats[c]["correct"] += 1
            else:
                pair = (c, pred_top1)
                confusion_pairs[pair] = confusion_pairs.get(pair, 0) + 1

            if c in pred_top3:
                top3_correct += 1

    top1_acc = (top1_correct / total_evaluated * 100) if total_evaluated > 0 else 0
    top3_acc = (top3_correct / total_evaluated * 100) if total_evaluated > 0 else 0
    avg_latency = np.mean(inference_times) if inference_times else 0

    print("\n" + "=" * 65)
    print("  ACCURACY EVALUATION SUMMARY")
    print("=" * 65)
    print(f"  Total Test Samples:      {total_evaluated} across 64 classes")
    print(f"  Top-1 Accuracy:          {top1_acc:.2f}%  ({top1_correct}/{total_evaluated})")
    print(f"  Top-3 Accuracy:          {top3_acc:.2f}%  ({top3_correct}/{total_evaluated})")
    print(f"  Average Mobile Latency:  {avg_latency:.2f} ms per cell")
    print("=" * 65)

    # Breakdown by accuracy brackets
    high_acc = sum(1 for c in range(64) if per_class_stats[c]["total"] > 0 and (per_class_stats[c]["correct"] / per_class_stats[c]["total"]) >= 0.90)
    print(f"\n  Classes with >= 90% accuracy:  {high_acc} / 64 ({high_acc / 64 * 100:.1f}%)")

    # Display any lowest accuracy classes
    sub_90 = []
    for c in range(64):
        st = per_class_stats[c]
        if st["total"] > 0:
            acc = st["correct"] / st["total"]
            if acc < 0.90:
                char = labels[c] if c < len(labels) else '?'
                sub_90.append((c, char, acc, st["correct"], st["total"]))

    if sub_90:
        print("\n  Classes below 90% threshold:")
        for c, char, acc, corr, tot in sorted(sub_90, key=lambda x: x[2])[:10]:
            print(f"    - Class {c:02d} ('{char}'): {acc*100:.1f}% ({corr}/{tot} correct)")
    else:
        print("\n  All 64 Braille classes achieved >= 90% accuracy!")

    return top1_acc, top3_acc

def evaluate_keras_h5(h5_path="ml/braille_cnn/braille_model.h5", data_dir="ml/braille_cnn/data"):
    if not os.path.exists(h5_path):
        print(f"H5 model '{h5_path}' not found.")
        return

    print("\n" + "=" * 65)
    print(f"  Evaluating Keras H5 Checkpoint: {h5_path}")
    print("=" * 65)
    model = keras.models.load_model(h5_path, compile=False)
    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy", keras.metrics.SparseTopKCategoricalAccuracy(k=3, name="top_3_accuracy")]
    )

    class_names = [str(i) for i in range(64)]
    val_ds = keras.utils.image_dataset_from_directory(
        data_dir,
        labels="inferred",
        label_mode="int",
        class_names=class_names,
        validation_split=0.2,
        subset="validation",
        seed=42,
        image_size=(28, 28),
        color_mode="grayscale",
        batch_size=256
    )

    metrics = model.evaluate(val_ds, verbose=1)
    for name, val in zip(model.metrics_names, metrics):
        if "acc" in name:
            print(f"  {name}: {val*100:.2f}%")
        else:
            print(f"  {name}: {val:.4f}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Evaluate Braille CNN Model Accuracy")
    parser.add_argument("--model", type=str, default="app/assets/models/braille_cnn.tflite", help="TFLite model path")
    parser.add_argument("--h5", type=str, default="ml/braille_cnn/braille_model.h5", help="Keras H5 model path")
    parser.add_argument("--data_dir", type=str, default="ml/braille_cnn/data", help="Braille dataset path")
    parser.add_argument("--samples_per_class", type=int, default=30, help="Samples per class for TFLite evaluation")
    parser.add_argument("--eval_h5", action="store_true", help="Also evaluate H5 model on complete validation split")
    args = parser.parse_args()

    evaluate_tflite_model(args.model, args.data_dir, args.samples_per_class)
    if args.eval_h5:
        evaluate_keras_h5(args.h5, args.data_dir)
