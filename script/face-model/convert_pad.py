"""Convert pinned MiniFASNet checkpoints to local FP32 Core ML PAD models.

Run in an isolated environment with requirements-pad.txt. Downloads are hash-checked before
import or deserialization, and torch.load uses weights_only=True. No camera or user images
are needed: synthetic parity fixtures test conversion and pixel preprocessing only.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request

import coremltools as ct
import cv2
import numpy as np
import torch


SOURCE_COMMIT = "b6d5f04ad78778917853b25c778acef6d5626d15"
SOURCE_URL = f"https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/{SOURCE_COMMIT}"
MODEL_IDENTIFIER = "minifasnet-v2-v1se-b6d5f04-fp32-v1"
ARCHITECTURE_SHA256 = "e498c4ec5e1ddfaba62b941a126c19d65aa564999f3309661fe43ee8bf38acd7"
VARIANTS = [
    ("MiniFASNetV2", "2.7_80x80_MiniFASNetV2.pth", 2.7,
     "a5eb02e1843f19b5386b953cc4c9f011c3f985d0ee2bb9819eea9a142099bec0"),
    ("MiniFASNetV1SE", "4_0_0_80x80_MiniFASNetV1SE.pth", 4.0,
     "84ee1d37d96894d5e82de5a57df044ef80a58be2b218b5ed7cdfd875ec2f5990"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(path: str, destination: Path, expected: str | None) -> Path:
    if destination.exists() and expected and sha256(destination) == expected:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".download")
    try:
        with urllib.request.urlopen(f"{SOURCE_URL}/{path}", timeout=60) as response, temporary.open("wb") as handle:
            shutil.copyfileobj(response, handle)
        actual = sha256(temporary)
        if expected and actual != expected:
            raise ValueError(f"Unexpected SHA-256 for {path}: {actual}")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    return destination


def source_module(cache: Path):
    source = download("src/model_lib/MiniFASNet.py", cache / "MiniFASNet.py", ARCHITECTURE_SHA256)
    spec = importlib.util.spec_from_file_location("notchy_pinned_minifasnet", source)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the pinned model architecture")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rgb(generator: str, seed: int, width: int = 80, height: int = 80) -> np.ndarray:
    if generator == "noise":
        state = seed
        values = []
        for _ in range(width * height * 3):
            state ^= (state << 13) & 0xFFFFFFFF
            state ^= state >> 17
            state ^= (state << 5) & 0xFFFFFFFF
            state &= 0xFFFFFFFF
            values.append(state >> 24)
        return np.asarray(values, dtype=np.uint8).reshape(height, width, 3)
    if generator == "gradient":
        rows, columns = np.indices((height, width), dtype=np.int32)
        return np.stack((rows * 255 // (height - 1), columns * 255 // (width - 1),
                         (rows + columns) * 255 // (height + width - 2)), axis=2).astype(np.uint8)
    if generator == "solid":
        return np.full((height, width, 3), seed, dtype=np.uint8)
    raise ValueError(generator)


def tensor(image: np.ndarray) -> np.ndarray:
    # Upstream uses cv2.imread and its custom ToTensor: BGR, 0...255, no division by 255.
    return image[:, :, ::-1].transpose(2, 0, 1).astype(np.float32)[None].copy()


def crop(image: np.ndarray, bounds: list[float], scale: float) -> np.ndarray:
    height, width = image.shape[:2]
    epsilon = 1e-7
    x = int(np.floor(bounds[0] * width + epsilon))
    y = int(np.floor(bounds[1] * height + epsilon))
    box_width = int(np.ceil((bounds[0] + bounds[2]) * width - epsilon)) - x
    box_height = int(np.ceil((bounds[1] + bounds[3]) * height - epsilon)) - y
    scale = min(scale, (height - 1) / box_height, (width - 1) / box_width)
    new_width, new_height = box_width * scale, box_height * scale
    cx, cy = x + box_width / 2, y + box_height / 2
    left, top = cx - new_width / 2, cy - new_height / 2
    right, bottom = cx + new_width / 2, cy + new_height / 2
    if left < 0:
        right -= left
        left = 0
    if top < 0:
        bottom -= top
        top = 0
    if right > width - 1:
        left -= right - width + 1
        right = width - 1
    if bottom > height - 1:
        top -= bottom - height + 1
        bottom = height - 1
    return cv2.resize(image[int(top):int(bottom) + 1, int(left):int(right) + 1],
                      (80, 80), interpolation=cv2.INTER_LINEAR)


def softmax(logits: np.ndarray) -> np.ndarray:
    exponents = np.exp(logits.astype(np.float64) - np.max(logits))
    return (exponents / np.sum(exponents)).astype(np.float32).reshape(3)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True, help="isolated download/cache directory")
    parser.add_argument("--out", type=Path, required=True, help="model resource directory")
    parser.add_argument("--fixture", type=Path, required=True, help="synthetic parity fixture JSON")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    module = source_module(args.cache)
    torch.set_num_threads(1)
    fixture = {"modelIdentifier": MODEL_IDENTIFIER, "samples": [], "cropSamples": []}
    for generator, seed in [("solid", 0), ("solid", 127), ("solid", 255),
                            ("gradient", 0), ("noise", 1), ("noise", 42)]:
        fixture["samples"].append({"generator": generator, "seed": seed, "scores": {}})
    for scale, bounds in [(2.7, [0.05, 0.1, 0.3, 0.4]), (4.0, [0.65, 0.55, 0.3, 0.4])]:
        pixels = crop(rgb("gradient", 0, 160, 120), bounds, scale)
        fixture["cropSamples"].append({
            "width": 160, "height": 120, "generator": "gradient", "seed": 0,
            "bounds": bounds, "scale": scale,
            "bgrTensorBase64": base64.b64encode(tensor(pixels).astype(np.uint8).tobytes()).decode(),
        })
    manifest = {
        "identifier": MODEL_IDENTIFIER, "sourceCommit": SOURCE_COMMIT,
        "sourceRepository": "https://github.com/minivision-ai/Silent-Face-Anti-Spoofing",
        "architectureSHA256": ARCHITECTURE_SHA256, "precision": "fp32",
        "input": {"name": "image", "shape": [1, 3, 80, 80], "channels": "BGR", "range": [0, 255]},
        "output": {"name": "logits", "classCount": 3, "liveClass": 1},
        "tools": {"coremltools": ct.__version__, "torch": torch.__version__,
                  "numpy": np.__version__, "opencv": cv2.__version__},
        "parityTolerance": 0.001, "models": [],
        "validation": "Synthetic conversion parity only; no biometric/PAD accuracy or live-camera validation.",
    }
    for name, filename, scale, expected_hash in VARIANTS:
        checkpoint = download(f"resources/anti_spoof_models/{filename}", args.cache / filename, expected_hash)
        network = getattr(module, name)(conv6_kernel=(5, 5)).eval()
        state = torch.load(checkpoint, map_location="cpu", weights_only=True)
        state = {key.removeprefix("module."): value for key, value in state.items()}
        network.load_state_dict(state, strict=True)
        example = torch.from_numpy(tensor(rgb("gradient", 0)))
        with torch.no_grad():
            traced = torch.jit.trace(network, example, check_trace=True).eval()
        converted = ct.convert(
            traced, convert_to="mlprogram", source="pytorch",
            inputs=[ct.TensorType(name="image", shape=(1, 3, 80, 80), dtype=np.float32)],
            outputs=[ct.TensorType(name="logits", dtype=np.float32)],
            compute_precision=ct.precision.FLOAT32, minimum_deployment_target=ct.target.macOS14,
        )
        converted.author = "Minivision; Core ML conversion for Notchy"
        converted.license = "Upstream repository: Apache-2.0; see MiniFASNet-NOTICE.md and MiniFASNet-LICENSE.txt"
        converted.short_description = f"{name}: contextual 80×80 BGR pixels (0...255) to three PAD logits."
        converted.version = "1"
        converted.user_defined_metadata.update({
            "notchy.pad.identifier": MODEL_IDENTIFIER, "notchy.pad.variant": name,
            "notchy.pad.sourceCommit": SOURCE_COMMIT, "notchy.pad.sourceSHA256": expected_hash,
            "notchy.pad.cropScale": str(scale), "notchy.pad.liveClass": "1",
            "notchy.pad.precision": "fp32", "notchy.pad.pixelRange": "0...255", "notchy.pad.channels": "BGR",
        })
        output = args.out / f"{name}.mlpackage"
        if output.exists() and not args.overwrite:
            raise FileExistsError(f"{output} exists; use --overwrite to replace this model")
        with tempfile.TemporaryDirectory(prefix="notchy-pad-convert-") as temporary:
            temporary_package = Path(temporary) / output.name
            converted.save(str(temporary_package))
            if output.exists():
                shutil.rmtree(output)
            shutil.copytree(temporary_package, output)
        checked = ct.models.MLModel(str(output), compute_units=ct.ComputeUnit.CPU_ONLY)
        maximum_error = 0.0
        for sample in fixture["samples"]:
            values = tensor(rgb(sample["generator"], sample["seed"]))
            with torch.no_grad():
                expected = torch.softmax(network(torch.from_numpy(values)), dim=1).numpy().reshape(3)
            actual = softmax(checked.predict({"image": values})["logits"])
            error = float(np.max(np.abs(actual - expected)))
            maximum_error = max(maximum_error, error)
            if error > 0.001 or int(np.argmax(actual)) != int(np.argmax(expected)):
                raise ValueError(f"{name} conversion parity failed: {sample['generator']} {error}")
            sample["scores"][name] = [float(value) for value in expected]
        files = {str(path.relative_to(output)): sha256(path) for path in sorted(output.rglob("*")) if path.is_file()}
        manifest["models"].append({"name": name, "checkpoint": filename, "checkpointSHA256": expected_hash,
                                    "cropScale": scale, "packageFiles": files,
                                    "maximumSyntheticProbabilityDifference": maximum_error})
        print(f"{name}: FP32 Core ML saved; maximum synthetic probability difference {maximum_error:.8g}", flush=True)
    download("LICENSE", args.out / "MiniFASNet-LICENSE.txt", None)
    (args.out / "MiniFASNet-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    args.fixture.parent.mkdir(parents=True, exist_ok=True)
    args.fixture.write_text(json.dumps(fixture, indent=2) + "\n")
    print("Parity checks cover conversion only; real-camera attack rejection remains unmeasured.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
