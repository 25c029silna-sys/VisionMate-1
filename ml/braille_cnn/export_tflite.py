import os
import argparse
import tensorflow as tf

def export_tflite(model_path: str, output_path: str, quantize: bool = True):
    """
    Converts trained Keras H5 model into TensorFlow Lite format with post-training quantization.
    """
    print(f"Exporting model from '{model_path}' to '{output_path}'...")
    if not os.path.exists(model_path):
        print(f"Model path '{model_path}' not found. Generating default Braille CNN model for export...")
        from train import create_braille_cnn
        model = create_braille_cnn()
    else:
        model = tf.keras.models.load_model(model_path)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if quantize:
        print("Applying float16 post-training quantization for mobile optimization...")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]

    tflite_model = converter.convert()

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(tflite_model)
    print(f"TFLite model exported successfully to '{output_path}' ({len(tflite_model)} bytes).")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Export Braille CNN to TFLite")
    parser.add_argument("--model_path", type=str, default="ml/braille_cnn/braille_model.h5", help="Saved Keras model path")
    parser.add_argument("--output_path", type=str, default="app/assets/models/braille_cnn.tflite", help="Destination TFLite file")
    parser.add_argument("--no_quantize", action="store_true", help="Disable quantization")
    args = parser.parse_args()

    export_tflite(args.model_path, args.output_path, quantize=not args.no_quantize)

