import os
import argparse
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

def create_braille_cnn(input_shape=(28, 28, 1), num_classes=64):
    """
    Builds a high-accuracy Convolutional Neural Network for 6-dot Braille cell classification.
    Input: 28x28 grayscale Braille cell image patch [0..255].
    Output: Softmax probability distribution over 64 possible Braille dot combinations (2^6 = 64).
    """
    inputs = layers.Input(shape=input_shape, name="braille_cell_input")
    x = layers.Rescaling(1.0 / 255.0, name="rescaling")(inputs)

    # Smartphone camera variations: minor rotations and translations
    data_augmentation = keras.Sequential([
        layers.RandomRotation(0.04),
        layers.RandomTranslation(0.03, 0.03),
    ], name="braille_augmentation")
    x = data_augmentation(x)

    # Stage 1: 28x28 -> 14x14
    x = layers.Conv2D(32, (3, 3), padding="same", activation="relu", name="conv1_1")(x)
    x = layers.BatchNormalization(name="bn1_1")(x)
    x = layers.Conv2D(32, (3, 3), padding="same", activation="relu", name="conv1_2")(x)
    x = layers.BatchNormalization(name="bn1_2")(x)
    x = layers.MaxPooling2D((2, 2), name="pool1")(x)
    x = layers.Dropout(0.2, name="drop1")(x)

    # Stage 2: 14x14 -> 7x7
    x = layers.Conv2D(64, (3, 3), padding="same", activation="relu", name="conv2_1")(x)
    x = layers.BatchNormalization(name="bn2_1")(x)
    x = layers.Conv2D(64, (3, 3), padding="same", activation="relu", name="conv2_2")(x)
    x = layers.BatchNormalization(name="bn2_2")(x)
    x = layers.MaxPooling2D((2, 2), name="pool2")(x)
    x = layers.Dropout(0.25, name="drop2")(x)

    # Stage 3: 7x7 -> 3x3
    x = layers.Conv2D(128, (3, 3), padding="same", activation="relu", name="conv3_1")(x)
    x = layers.BatchNormalization(name="bn3_1")(x)
    x = layers.MaxPooling2D((2, 2), name="pool3")(x)
    x = layers.Dropout(0.3, name="drop3")(x)

    # Dense Classification Head
    x = layers.Flatten(name="flatten")(x)
    x = layers.Dense(256, activation="relu", name="dense1")(x)
    x = layers.BatchNormalization(name="bn_dense")(x)
    x = layers.Dropout(0.4, name="drop_dense")(x)
    outputs = layers.Dense(num_classes, activation="softmax", name="braille_predictions")(x)

    model = keras.Model(inputs=inputs, outputs=outputs, name="Braille_CNN")
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=[
            "accuracy",
            keras.metrics.SparseTopKCategoricalAccuracy(k=3, name="top_3_accuracy")
        ]
    )
    return model

# Backward compatibility alias
create_braille_mobilenet_v3_small = create_braille_cnn

def plot_training_curves(history, output_path="ml/braille_cnn/training_curves.png"):
    """Plot accuracy and loss training history curves with Matplotlib."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    acc = history.history.get("accuracy", [])
    val_acc = history.history.get("val_accuracy", [])
    loss = history.history.get("loss", [])
    val_loss = history.history.get("val_loss", [])
    epochs_range = range(1, len(acc) + 1)

    # Accuracy
    ax1.plot(epochs_range, acc, label="Training Accuracy", color="#1976D2", linewidth=2)
    if val_acc:
        ax1.plot(epochs_range, val_acc, label="Validation Accuracy", color="#388E3C", linewidth=2)
    top3 = history.history.get("val_top_3_accuracy", [])
    if top3:
        ax1.plot(epochs_range, top3, label="Val Top-3 Accuracy", color="#F57C00", linestyle=":", linewidth=2)
    ax1.set_title("Braille CNN Classification Accuracy", fontsize=12, fontweight="bold")
    ax1.set_xlabel("Epochs")
    ax1.set_ylabel("Accuracy")
    ax1.legend(loc="lower right")
    ax1.grid(True, alpha=0.3)

    # Loss
    ax2.plot(epochs_range, loss, label="Training Loss", color="#D32F2F", linewidth=2)
    if val_loss:
        ax2.plot(epochs_range, val_loss, label="Validation Loss", color="#7B1FA2", linewidth=2)
    ax2.set_title("Braille CNN Cross-Entropy Loss", fontsize=12, fontweight="bold")
    ax2.set_xlabel("Epochs")
    ax2.set_ylabel("Loss")
    ax2.legend(loc="upper right")
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    plt.savefig(output_path, dpi=150)
    print(f"Training curves successfully saved to '{output_path}'")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description="Train Braille CNN Classifier")
    parser.add_argument("--data_dir", type=str, default="ml/braille_cnn/data", help="Directory containing Braille dataset (0..63 subdirs)")
    parser.add_argument("--epochs", type=int, default=12, help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=128, help="Batch size")
    parser.add_argument("--output_model", type=str, default="ml/braille_cnn/braille_model.h5", help="Saved Keras model path")
    args = parser.parse_args()

    print("=" * 60)
    print(" VisionMate Braille CNN Classifier Training")
    print("=" * 60)

    print("Building Braille CNN model...")
    model = create_braille_cnn()
    model.summary()

    # Strict numerical 0..63 class naming to prevent string sorting anomalies
    class_names = [str(i) for i in range(64)]

    print(f"\nLoading dataset from '{args.data_dir}' (64 classes, 28x28 grayscale)...")
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

    autotune = tf.data.AUTOTUNE
    train_ds = train_ds.cache().prefetch(buffer_size=autotune)
    val_ds = val_ds.cache().prefetch(buffer_size=autotune)

    os.makedirs(os.path.dirname(args.output_model), exist_ok=True)

    callbacks = [
        keras.callbacks.ModelCheckpoint(
            filepath=args.output_model,
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1
        ),
        keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=2,
            min_lr=1e-5,
            verbose=1
        ),
        keras.callbacks.EarlyStopping(
            monitor="val_accuracy",
            patience=4,
            restore_best_weights=True,
            verbose=1
        ),
    ]

    print(f"\nStarting training for up to {args.epochs} epochs with batch size {args.batch_size}...")
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=args.epochs,
        callbacks=callbacks
    )

    # Evaluate final/best model on validation set
    print("\n--- Final Validation Set Evaluation ---")
    val_metrics = model.evaluate(val_ds, verbose=1)
    for name, val in zip(model.metrics_names, val_metrics):
        print(f"  {name}: {val:.4f}")

    plot_training_curves(history)

    # Ensure model is saved if ModelCheckpoint was not triggered
    if not os.path.exists(args.output_model):
        model.save(args.output_model)
    print(f"\nBest trained model saved to '{args.output_model}'")

if __name__ == '__main__':
    main()
