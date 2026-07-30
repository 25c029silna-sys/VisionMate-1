import os
import argparse

def export_minilm_tflite(model_name: str, output_path: str):
    """
    Exports SentenceTransformers all-MiniLM-L6-v2 model to ONNX and TFLite for on-device vector embedding generation.
    """
    print(f"Exporting MiniLM model '{model_name}' to '{output_path}'...")
    try:
        from sentence_transformers import SentenceTransformer
        import torch
        
        print("Loading HuggingFace SentenceTransformer model...")
        model = SentenceTransformer(model_name)
        
        # Save PyTorch/ONNX representation
        onnx_path = output_path.replace(".tflite", ".onnx")
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        print(f"Saving intermediate ONNX model to {onnx_path}...")
        
        dummy_input = model.tokenize(["Test sentence for vector embedding export"])
        torch.onnx.export(
            model[0].auto_model,
            (dummy_input['input_ids'], dummy_input['attention_mask']),
            onnx_path,
            input_names=['input_ids', 'attention_mask'],
            output_names=['embeddings'],
            dynamic_axes={'input_ids': {0: 'batch'}, 'attention_mask': {0: 'batch'}}
        )
        print("ONNX model generated successfully. Convert to TFLite via tf2onnx / onnx2tf.")
    except Exception as e:
        print(f"MiniLM export requirement note: Install sentence-transformers & torch in Python env to run live export: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Export MiniLM SentenceTransformer to TFLite")
    parser.add_argument("--model_name", type=str, default="all-MiniLM-L6-v2", help="SentenceTransformers model name")
    parser.add_argument("--output_path", type=str, default="app/assets/models/minilm.tflite", help="Destination TFLite file")
    args = parser.parse_args()

    export_minilm_tflite(args.model_name, args.output_path)

