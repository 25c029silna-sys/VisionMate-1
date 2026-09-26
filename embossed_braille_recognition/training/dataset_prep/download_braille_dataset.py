import os
import sys
import urllib.request
import subprocess
from pathlib import Path

# Paths
ROOT_DIR = Path(__file__).resolve().parent.parent
ANGELINA_DIR = ROOT_DIR / "AngelinaReader"
DSBI_DIR = ANGELINA_DIR / "DSBI"
WEIGHTS_DIR = ANGELINA_DIR / "weights"
MODEL_WEIGHTS_PATH = WEIGHTS_DIR / "model.t7"
RAW_DATASET_DIR = ROOT_DIR / "ml" / "braille_cnn" / "data" / "raw"
PROCESSED_DATA_DIR = ROOT_DIR / "ml" / "braille_cnn" / "data"

DSBI_GIT_REPO = "https://github.com/yeluo1994/DSBI.git"
PRETRAINED_MODEL_URL = "http://ovdv.ru/files/retina_chars_eced60.clr.008"

def download_file(url: str, target_path: Path):
    """Downloads a file with progress updates."""
    print(f"Downloading {url} to {target_path}...")
    target_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        def reporthook(blocknum, blocksize, totalsize):
            readsofar = blocknum * blocksize
            if totalsize > 0:
                percent = readsofar * 100 / totalsize
                s = f"\rDownloading... {percent:.1f}% ({readsofar / (1024*1024):.1f} MB)"
                sys.stdout.write(s)
                sys.stdout.flush()
            else:
                sys.stdout.write(f"\rDownloaded {readsofar / (1024*1024):.1f} MB...")
                sys.stdout.flush()

        urllib.request.urlretrieve(url, target_path, reporthook=reporthook)
        print("\nDownload complete!")
    except Exception as e:
        print(f"\nFailed to download {url}: {e}")

def setup_dsbi_dataset():
    """Clones or updates the DSBI dataset."""
    if not DSBI_DIR.exists() or not list(DSBI_DIR.glob("*")):
        print(f"Cloning DSBI Dataset from {DSBI_GIT_REPO} into {DSBI_DIR}...")
        subprocess.run(["git", "clone", "--depth", "1", DSBI_GIT_REPO, str(DSBI_DIR)], check=True)
    else:
        print(f"DSBI dataset already present at {DSBI_DIR}.")

def setup_pretrained_weights():
    """Downloads pre-trained weights for Angelina Reader retina model."""
    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    if not MODEL_WEIGHTS_PATH.exists() or MODEL_WEIGHTS_PATH.stat().st_size < 1000:
        download_file(PRETRAINED_MODEL_URL, MODEL_WEIGHTS_PATH)
    else:
        print(f"Pretrained weights already exist at {MODEL_WEIGHTS_PATH}.")

def extract_braille_patches():
    """Extracts patches for lightweight Braille CNN training."""
    print("Extracting Braille cell patches for ML CNN training...")
    prepare_script = ROOT_DIR / "ml" / "braille_cnn" / "data" / "prepare_angelina_dataset.py"
    subprocess.run([
        sys.executable,
        str(prepare_script),
        "--raw_dir", str(DSBI_DIR),
        "--output_dir", str(PROCESSED_DATA_DIR)
    ], check=True)

def main():
    print("=== VisionMate Braille Recognition Setup ===")
    setup_pretrained_weights()
    setup_dsbi_dataset()
    extract_braille_patches()
    print("\n=== Dataset & Pretrained Models Setup Complete! ===")

if __name__ == '__main__':
    main()
