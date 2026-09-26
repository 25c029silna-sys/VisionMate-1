import os
import sys
import tensorflow as tf

def convert_braille_model(
    saved_model_dir="ml/yolov8_braille/yolov8_braille_saved_model",
    output_tflite_path="app/assets/models/yolov8_braille.tflite"
):
    print(f"Loading SavedModel from: {saved_model_dir}")
    if not os.path.exists(saved_model_dir):
        print(f"Error: Directory {saved_model_dir} does not exist!")
        sys.exit(1)

    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    print("Converting SavedModel to TFLite FlatBuffer...")
    tflite_model = converter.convert()

    os.makedirs(os.path.dirname(output_tflite_path), exist_ok=True)
    with open(output_tflite_path, "wb") as f:
        f.write(tflite_model)

    file_size_mb = len(tflite_model) / (1024 * 1024)
    print(f"Successfully exported TFLite model to: {output_tflite_path} ({file_size_mb:.2f} MB)")

    # Validate with TFLite Interpreter
    interpreter = tf.lite.Interpreter(model_content=tflite_model)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print("\n--- Verified TFLite Model Signatures ---")
    for i, inp in enumerate(input_details):
        print(f" Input  [{i}]: name='{inp['name']}', shape={inp['shape']}, dtype={inp['dtype'].__name__}")
    for i, out in enumerate(output_details):
        print(f" Output [{i}]: name='{out['name']}', shape={out['shape']}, dtype={out['dtype'].__name__}")
    print("----------------------------------------\n")

if __name__ == "__main__":
    saved_model_path = sys.argv[1] if len(sys.argv) > 1 else "ml/yolov8_braille/yolov8_braille_saved_model"
    output_path = sys.argv[2] if len(sys.argv) > 2 else "app/assets/models/yolov8_braille.tflite"
    convert_braille_model(saved_model_path, output_path)
