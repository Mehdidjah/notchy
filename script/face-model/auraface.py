"""Pinned AuraFace artifact and the input contract shared by conversion and verification.

The trained weight is Apache-2.0, published by fal. No inference code or weights from
unrelated model packages are downloaded. See Model/AuraFace-LICENSE.md for provenance.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import urllib.request


REVISION = "af6d057c9b0ec4071d4c49c80e3539258798b609"
SOURCE_SHA256 = "a7933ea5330113b01c9b60351d8f4c33003f145d8470ac5f0e52ee2effe25c60"
SOURCE_SIZE = 260694151
SOURCE_URL = f"https://huggingface.co/fal/AuraFace-v1/resolve/{REVISION}/glintr100.onnx"
MODEL_IDENTIFIER = "auraface-v1-r1"
CHIP_SIZE = 112
DESCRIPTOR_LENGTH = 512
INPUT_NAME = "image"
OUTPUT_NAME = "descriptor"

# Five-point alignment constants documented by the MIT-licensed InsightFace inference
# implementation. Ordered by the image: left eye, right eye, nose tip, left/right mouth.
# They describe pixel coordinates in a 112 x 112 unmirrored RGB chip, with no extra padding.
ALIGNMENT_TARGET = (
    (38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366),
    (41.5493, 92.3655), (70.7299, 92.2041),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_source(path: Path) -> str:
    if path.stat().st_size != SOURCE_SIZE:
        raise ValueError(f"wrong source size: {path.stat().st_size}; expected {SOURCE_SIZE}")
    actual = sha256_file(path)
    if actual != SOURCE_SHA256:
        raise ValueError(f"wrong source SHA-256: {actual}")
    return actual


def download_source(path: Path) -> None:
    """Fetch only the pinned model, verify before publishing, and never replace a file."""
    if path.exists():
        verify_source(path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".partial")
    if temporary.exists():
        raise FileExistsError(f"remove or inspect the previous incomplete download: {temporary}")
    try:
        with urllib.request.urlopen(SOURCE_URL, timeout=120) as response, temporary.open("xb") as output:
            for block in iter(lambda: response.read(1 << 20), b""):
                output.write(block)
        verify_source(temporary)
        temporary.rename(path)
    finally:
        temporary.unlink(missing_ok=True)
