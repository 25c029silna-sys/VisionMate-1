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

def main():
    parser = argparse.ArgumentParser(description="Train Braille CNN Classifier")
    parser.add_argument("--data_dir", type=str, default="ml/braille_cnn/data", help="Directory containing Braille dataset")
    parser.add_argument("--epochs", type=int, default=5, help="Training epochs")
    parser.add_argument("--batch_size", type=int, default=64, help="Batch size")
    parser.add_argument("--output_model", type=str, default="ml/braille_cnn/braille_model.h5", help="Saved Keras model path")
    args = parser.parse_args()

    print("Building Braille CNN model...")
    model = create_braille_cnn()
    model.summary()

    # Explicit integer class names list 0..63 to prevent string sorting bug (['0', '1', '10', ...])
    class_names = [str(i) for i in range(64)]

    print(f"Loading dataset from {args.data_dir} with strict 0..63 class ordering...")
    train_ds = keras.utils.image_dataset_from_directory(
        args.data_dir,
        labels="inferred",
        label_mode="int",
        class_names=class_names,
        validation_split=0.2,
        subset="training",
        seed=42,
        image_size=(28, 28),
        color_mode="grayscale",
        batch_size=args.batch_size
    )
    val_ds = keras.utils.image_dataset_from_directory(
        args.data_dir,
        labels="inferred",
        label_mode="int",
        class_names=class_names,
        validation_split=0.2,
        subset="validation",
        seed=42,
        image_size=(28, 28),
        color_mode="grayscale",
        batch_size=args.batch_size
    )
    history = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)

    plot_training_curves(history)
    os.makedirs(os.path.dirname(args.output_model), exist_ok=True)
    model.save(args.output_model)
    print(f"Model saved successfully to {args.output_model}")

if __name__ == '__main__':
    main()
