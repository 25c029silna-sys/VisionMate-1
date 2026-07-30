import argparse
from ultralytics import YOLO

def main():
    parser = argparse.ArgumentParser(description="Fine-tune YOLOv8 Nano for Obstacle Detection")
    parser.add_argument("--data", type=str, default="ml/yolov8_obstacle/data.yaml", help="Path to dataset data.yaml")
    parser.add_argument("--epochs", type=int, default=30, help="Training epochs")
    parser.add_argument("--imgsz", type=int, default=640, help="Image size")
    parser.add_argument("--output_weights", type=str, default="ml/yolov8_obstacle/yolov8n_obstacle.pt", help="Saved weights path")
    args = parser.parse_args()

    print("Initializing YOLOv8 Nano model...")
    model = YOLO("yolov8n.pt")

    try:
        print(f"Training YOLOv8n on dataset '{args.data}' for {args.epochs} epochs...")
        model.train(data=args.data, epochs=args.epochs, imgsz=args.imgsz)
        model.save(args.output_weights)
        print(f"Weights saved successfully to {args.output_weights}")
    except Exception as e:
        print(f"Dataset note: Provide valid YAML configuration at '{args.data}' to execute full fine-tuning. ({e})")

if __name__ == '__main__':
    main()

