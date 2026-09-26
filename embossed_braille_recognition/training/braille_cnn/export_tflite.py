import os
import argparse
import tensorflow as tf

def export_tflite(model_path: str, output_path: str, quantize: bool = True):
    """
    Converts trained Braille CNN model into TensorFlow Lite format with post-training quantization.
    Ensures input remains (1, 28, 28, 1) float32 and output (1, 64) float32 for Flutter compatibility.
    """
    print(f"Exporting model from '{model_path}' to '{output_path}'...")
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file '{model_path}' does not exist! Please train the model first with 'python ml/braille_cnn/train.py'.")

    model = tf.keras.models.load_model(model_path, compile=False)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    if quantize:
        print("Applying float16 post-training quantization for mobile size & execution optimization...")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]

    tflite_model = converter.convert()

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    file_size_kb = len(tflite_model) / 1024
    print(f"TFLite model exported successfully to '{output_path}' ({file_size_kb:.2f} KB).")

    # Verify input/output tensor signatures using TFLite Interpreter
    try:
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
    except Exception as e:
        print(f"Could not inspect TFLite interpreter signatures: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Export Braille CNN Model to TFLite")
    parser.add_argument("--model_path", type=str, default="ml/braille_cnn/braille_model.h5", help="Saved Keras model path")
    parser.add_argument("--output_path", type=str, default="app/assets/models/braille_cnn.tflite", help="Destination TFLite file")
    parser.add_argument("--no_quantize", action="store_true", help="Disable quantization")
    args = parser.parse_args()

    export_tflite(args.model_path, args.output_path, quantize=not args.no_quantize)
