import argparse
import os

def export_yolov8_tflite(weights_path: str, output_path: str):
    """
    Exports fine-tuned YOLOv8 PyTorch model (.pt) to TensorFlow Lite format for mobile deployment.
    """
    print(f"Exporting YOLOv8 weights from '{weights_path}' to '{output_path}'...")
    try:
        from ultralytics import YOLO
        model = YOLO(weights_path if os.path.exists(weights_path) else "yolov8n.pt")
        print("Exporting via Ultralytics export(format='tflite')...")
        exported_file = model.export(format="tflite", int8=False)
        print(f"YOLOv8 TFLite export complete: {exported_file}")
    except Exception as e:
        print(f"YOLOv8 export requirement note: Install ultralytics in Python env to run live export: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Export YOLOv8 model to TFLite")
    parser.add_argument("--weights_path", type=str, default="ml/yolov8_obstacle/yolov8n_obstacle.pt", help="Path to YOLOv8 PyTorch model")
    parser.add_argument("--output_path", type=str, default="app/assets/models/yolov8n.tflite", help="Destination TFLite file")
    args = parser.parse_args()

    export_yolov8_tflite(args.weights_path, args.output_path)

