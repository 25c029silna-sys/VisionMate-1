import os
import argparse
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

def create_braille_cnn(input_shape=(28, 28, 1), num_classes=64):
    """
    Builds a custom CNN classifier for 6-dot Braille cells.
    Input: 28x28 grayscale image patch of a single Braille cell.
    Output: Softmax probability over 64 possible Braille dot combinations (2^6 = 64).
    """
    data_augmentation = keras.Sequential([
        layers.RandomRotation(0.05),
        layers.RandomTranslation(0.05, 0.05),
        layers.RandomContrast(0.1),
    ], name="data_augmentation")

    inputs = layers.Input(shape=input_shape)
    x = data_augmentation(inputs)
    x = layers.Rescaling(1./255)(x)

    x = layers.Conv2D(32, kernel_size=(3, 3), activation='relu', padding='same')(x)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPooling2D(pool_size=(2, 2))(x)
    
    x = layers.Conv2D(64, kernel_size=(3, 3), activation='relu', padding='same')(x)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPooling2D(pool_size=(2, 2))(x)
    
    x = layers.Conv2D(128, kernel_size=(3, 3), activation='relu', padding='same')(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.3)(x)
    
    x = layers.Flatten()(x)
    x = layers.Dense(128, activation='relu')(x)
    x = layers.Dropout(0.4)(x)
    outputs = layers.Dense(num_classes, activation='softmax')(x)
    
    model = keras.Model(inputs=inputs, outputs=outputs, name="Braille_CNN")
    
    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    return model

def plot_training_curves(history, output_path="ml/braille_cnn/training_curves.png"):
    """Plot accuracy and loss training history curves with Matplotlib."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4))
    
    acc = history.history.get('accuracy', [])
    val_acc = history.history.get('val_accuracy', [])
    loss = history.history.get('loss', [])
    val_loss = history.history.get('val_loss', [])
    epochs_range = range(1, len(acc) + 1)
    
    ax1.plot(epochs_range, acc, label='Training Accuracy')
    if val_acc:
        ax1.plot(epochs_range, val_acc, label='Validation Accuracy')
    ax1.set_title('Braille CNN Accuracy')
    ax1.set_xlabel('Epochs')
    ax1.set_ylabel('Accuracy')
    ax1.legend(loc='lower right')
    
    ax2.plot(epochs_range, loss, label='Training Loss')
    if val_loss:
        ax2.plot(epochs_range, val_loss, label='Validation Loss')
    ax2.set_title('Braille CNN Loss')
    ax2.set_xlabel('Epochs')
    ax2.set_ylabel('Loss')
    ax2.legend(loc='upper right')
    
    plt.tight_layout()
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    plt.savefig(output_path, dpi=150)
    print(f"Training curves saved to {output_path}")
    plt.close()

def generate_synthetic_braille_data(num_samples=640):
    """Generates synthetic 28x28 6-dot Braille patches for testing when no real dataset is present."""
    X = np.zeros((num_samples, 28, 28, 1), dtype=np.float32)
    y = np.zeros((num_samples,), dtype=np.int32)
    
    # 6-dot coordinate grid inside 28x28 cell: (row, col)
    dot_coords = [(6, 8), (14, 8), (22, 8), (6, 20), (14, 20), (22, 20)]
    
    for i in range(num_samples):
        label = i % 64
        y[i] = label
        patch = np.zeros((28, 28), dtype=np.float32)
        # Render dots corresponding to 6-bit binary pattern of label
        for dot_idx, (r, c) in enumerate(dot_coords):
            if (label >> dot_idx) & 1:
                rr, cc = np.ogrid[:28, :28]
                mask = (rr - r)**2 + (cc - c)**2 <= 2**2
                patch[mask] = 255.0
        # Add background noise
        noise = np.random.normal(10.0, 5.0, (28, 28)).astype(np.float32)
        patch = np.clip(patch + noise, 0.0, 255.0)
        X[i] = patch.reshape(28, 28, 1)
        
    return X, y

def main():
    parser = argparse.ArgumentParser(description="Train Braille CNN Classifier")
    parser.add_argument("--data_dir", type=str, default="ml/braille_cnn/data", help="Directory containing Braille dataset")
    parser.add_argument("--epochs", type=int, default=10, help="Training epochs")
    parser.add_argument("--batch_size", type=int, default=32, help="Batch size")
    parser.add_argument("--output_model", type=str, default="ml/braille_cnn/braille_model.h5", help="Saved Keras model path")
    args = parser.parse_args()

    print("Building Braille CNN model...")
    model = create_braille_cnn()
    model.summary()

    has_images = False
    if os.path.exists(args.data_dir) and os.listdir(args.data_dir):
        try:
            print(f"Loading dataset from {args.data_dir}...")
            train_ds = keras.utils.image_dataset_from_directory(
                args.data_dir,
                validation_split=0.2,
                subset="training",
                seed=42,
                image_size=(28, 28),
                color_mode="grayscale",
                batch_size=args.batch_size
            )
            val_ds = keras.utils.image_dataset_from_directory(
                args.data_dir,
                validation_split=0.2,
                subset="validation",
                seed=42,
                image_size=(28, 28),
                color_mode="grayscale",
                batch_size=args.batch_size
            )
            history = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)
            has_images = True
        except Exception as e:
            print(f"Failed to load dataset from {args.data_dir}: {e}. Falling back to synthetic dataset.")
            has_images = False

    if not has_images:
        print("Generating synthetic Braille dataset for model training...")
        X, y = generate_synthetic_braille_data()
        split = int(0.8 * len(X))
        X_train, X_val = X[:split], X[split:]
        y_train, y_val = y[:split], y[split:]
        history = model.fit(X_train, y_train, validation_data=(X_val, y_val), batch_size=args.batch_size, epochs=args.epochs)


    plot_training_curves(history)
    os.makedirs(os.path.dirname(args.output_model), exist_ok=True)
    model.save(args.output_model)
    print(f"Model saved successfully to {args.output_model}")

if __name__ == '__main__':
    main()


