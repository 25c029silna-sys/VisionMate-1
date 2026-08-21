import os
import tensorflow as tf
from tensorflow import keras

def load_braille_dataset(data_dir: str = "ml/braille_cnn/data", batch_size: int = 32, image_size: tuple = (28, 28)):
    """
    Loads grayscale Braille cell dataset from 64 class folders.
    Returns (train_ds, val_ds).
    """
    if not os.path.exists(data_dir):
        raise FileNotFoundError(f"Dataset directory '{data_dir}' does not exist.")

    train_ds = keras.utils.image_dataset_from_directory(
        data_dir,
        validation_split=0.2,
        subset="training",
        seed=42,
        image_size=image_size,
        color_mode="grayscale",
        batch_size=batch_size,
    )

    val_ds = keras.utils.image_dataset_from_directory(
        data_dir,
        validation_split=0.2,
        subset="validation",
        seed=42,
        image_size=image_size,
        color_mode="grayscale",
        batch_size=batch_size,
    )

    return train_ds, val_ds
