#!/usr/bin/env python3
"""
Standalone script to upload an already-recorded video file to Telegram
Saved Messages, reusing the Telegram uploader class that ships with
TikTok Live Recorder (src/upload/telegram.py).

Usage:
    uv run python upload_video.py /path/to/video.mp4
"""
import sys
import argparse
from pathlib import Path

# The project's modules (upload.telegram, utils.*, core.*) are written to be
# imported with "src" as the root (that's how src/main.py works when you run
# `uv run python src/main.py`). Since this script lives at the repo root,
# we add src/ to sys.path manually so the same imports work here.
SRC_DIR = Path(__file__).resolve().parent / "src"
sys.path.insert(0, str(SRC_DIR))

try:
    from upload.telegram import Telegram
    from utils.logger_manager import logger
except ImportError as e:
    print(f"Could not import project modules from {SRC_DIR}: {e}")
    print("Make sure you're running this from the repo root "
          "(the folder that contains the 'src' directory).")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Upload a recorded video to Telegram Saved Messages."
    )
    parser.add_argument(
        "file_path",
        help="Path to the .mp4 (or other) file to upload",
    )
    args = parser.parse_args()

    file_path = Path(args.file_path)
    if not file_path.is_file():
        logger.error(f"File not found: {file_path}")
        sys.exit(1)

    logger.info(f"Preparing to upload: {file_path}")
    uploader = Telegram()
    uploader.upload(str(file_path))


if __name__ == "__main__":
    main()
