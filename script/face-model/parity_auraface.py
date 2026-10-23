"""Verify AuraFace Core ML numerical parity and measure its local inference latency.

    python3 -I script/face-model/parity_auraface.py \
        --onnx /tmp/notchy-auraface/glintr100.onnx \
        --package /tmp/notchy-auraface/AuraFace-fp32.mlpackage \
        --compute-units cpu --report /tmp/notchy-auraface/fp32-parity.json

Synthetic images verify the conversion and RGB input contract, not recognition accuracy,
spoof resistance, or an authentication threshold. Optional --chips may add consenting
subjects' already-aligned 112x112 crops; the report stores hashes and aggregate metrics,
never those source images. --fixture is an explicit opt-in output for synthetic vectors.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import resource
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

import auraface  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402


def synthetic_chips() -> dict[str, np.ndarray]:
    size = auraface.CHIP_SIZE
    row, col = np.mgrid[:size, :size]
    cases = {
        f"solid-{level}": np.full((size, size, 3), level, dtype=np.uint8)
        for level in (0, 127, 255)
    }
    ramp = (col * 255 // (size - 1)).astype(np.uint8)
    for channel in range(3):
        value = np.full((size, size, 3), 64, dtype=np.uint8)
        value[:, :, channel] = ramp
        cases[f"channel-ramp-{channel}"] = value
    cases["gradient"] = np.stack([
        row * 255 // (size - 1), col * 255 // (size - 1),
        (row + col) * 255 // (2 * (size - 1)),
    ], axis=-1).astype(np.uint8)
    for seed in (1, 23, 123456789):
        state = seed
        noise = np.empty(size * size * 3, dtype=np.uint8)
        for index in range(noise.size):
            state ^= (state << 13) & 0xFFFFFFFF
            state ^= state >> 17
            state ^= (state << 5) & 0xFFFFFFFF
            noise[index] = state >> 24
        cases[f"xorshift32-{seed}"] = noise.reshape(size, size, 3)
    checker = ((row // 8 + col // 8) % 2 * 255).astype(np.uint8)
    cases["checker"] = np.stack([checker, 255 - checker, checker // 2], axis=-1)
    rings = (row - size // 2) ** 2 + (col - size // 2) ** 2
    cases["rings"] = np.stack([
        rings // 9 % 256, rings // 13 % 256, rings // 17 % 256,
    ], axis=-1).astype(np.uint8)
    return cases


def normalized(vector) -> np.ndarray:
    value = np.asarray(vector, dtype=np.float64).reshape(-1)
    length = np.linalg.norm(value)
    if value.size != auraface.DESCRIPTOR_LENGTH or not np.isfinite(value).all() or length <= 1e-12:
        raise ValueError("invalid model descriptor")
    return value / length


def stats(milliseconds: list[float]) -> dict:
    return {"count": len(milliseconds), "p50Milliseconds": float(np.percentile(milliseconds, 50)),
            "p95Milliseconds": float(np.percentile(milliseconds, 95)),
            "maximumMilliseconds": float(max(milliseconds))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--onnx", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, help="write only synthetic reference descriptors")
    parser.add_argument("--chips", type=Path, help="optional existing aligned RGB112 images; no resizing")
    parser.add_argument("--compute-units", choices=("cpu", "cpu-ne", "all"), default="cpu-ne")
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=40)
    args = parser.parse_args()
    if args.iterations < 1 or args.warmup < 0:
        parser.error("iterations must be positive and warmup nonnegative")

    import coremltools as ct
    import onnxruntime as ort

    source_hash = auraface.verify_source(args.onnx)
    chips = synthetic_chips()
    synthetic_names = set(chips)
    extra_count = 0
    if args.chips:
        for path in sorted(args.chips.iterdir()):
            if path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".tiff", ".bmp"}:
                continue
            with Image.open(path) as opened:
                if opened.size != (112, 112):
                    raise ValueError(f"aligned crop must already be 112x112: {path.name}")
                rgb = np.asarray(opened.convert("RGB"))
            extra_count += 1
            chips[f"provided-crop-{extra_count}"] = rgb

    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    reference_started = time.perf_counter()
    reference = ort.InferenceSession(str(args.onnx), sess_options=options, providers=["CPUExecutionProvider"])
    reference_load_ms = (time.perf_counter() - reference_started) * 1000
    units = {"cpu": ct.ComputeUnit.CPU_ONLY, "cpu-ne": ct.ComputeUnit.CPU_AND_NE,
             "all": ct.ComputeUnit.ALL}[args.compute_units]
    load_started = time.perf_counter()
    model = ct.models.MLModel(str(args.package), compute_units=units)
    load_ms = (time.perf_counter() - load_started) * 1000
    metadata = model.user_defined_metadata
    if (metadata.get("notchy.faceModel.identifier") != auraface.MODEL_IDENTIFIER
            or metadata.get("notchy.faceModel.sourceSHA256") != source_hash
            or metadata.get("notchy.faceModel.descriptorLength") != "512"):
        raise ValueError("Core ML package provenance does not match the pinned source")
    precision = metadata.get("notchy.faceModel.precision")
    if precision not in {"fp32", "fp16"}:
        raise ValueError("unknown package precision")
    minimum_cosine = 0.99999 if precision == "fp32" else 0.9999
    first_ms = None
    comparison = []
    synthetic_vectors = []
    reference_ms = []
    model_vectors = []
    original_vectors = []
    for name, rgb in chips.items():
        blob = ((rgb.astype(np.float32) - np.float32(127.5)) / np.float32(127.5)).transpose(2, 0, 1)[None]
        started = time.perf_counter()
        expected = reference.run(["1333"], {"data": np.ascontiguousarray(blob)})[0].reshape(-1)
        reference_ms.append((time.perf_counter() - started) * 1000)
        image = Image.fromarray(rgb)
        started = time.perf_counter()
        actual = np.asarray(model.predict({"image": image})["descriptor"]).reshape(-1)
        elapsed = (time.perf_counter() - started) * 1000
        if first_ms is None:
            first_ms = elapsed
        unit_original, unit_actual = normalized(expected), normalized(actual)
        cosine = float(unit_original @ unit_actual)
        comparison.append({"case": name, "rgbSHA256": hashlib.sha256(rgb.tobytes()).hexdigest(),
                           "cosine": cosine, "maximumAbsoluteError": float(np.max(np.abs(expected - actual))),
                           "normalizedL2Error": float(np.linalg.norm(unit_original - unit_actual)),
                           "passed": cosine >= minimum_cosine})
        model_vectors.append(unit_actual)
        original_vectors.append(unit_original)
        if name in synthetic_names:
            synthetic_vectors.append({"generator": name, "rgbSHA256": comparison[-1]["rgbSHA256"],
                                      "descriptor": [float(value) for value in expected]})

    images = [Image.fromarray(value) for value in chips.values()]
    for index in range(args.warmup):
        model.predict({"image": images[index % len(images)]})
    timings = []
    for index in range(args.iterations):
        started = time.perf_counter()
        model.predict({"image": images[index % len(images)]})
        timings.append((time.perf_counter() - started) * 1000)
    original_matrix, model_matrix = np.asarray(original_vectors), np.asarray(model_vectors)
    pair_error = float(np.max(np.abs(original_matrix @ original_matrix.T - model_matrix @ model_matrix.T)))
    report = {
        "schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
        "modelIdentifier": auraface.MODEL_IDENTIFIER,
        "sourceRevision": auraface.REVISION, "sourceSHA256": source_hash,
        "package": str(args.package), "precision": precision,
        "packageFilesSHA256": {str(path.relative_to(args.package)): auraface.sha256_file(path)
                               for path in sorted(args.package.rglob("*")) if path.is_file()},
        "input": {"name": "image", "width": 112, "height": 112, "channels": "RGB",
                  "normalization": "(value - 127.5) / 127.5"},
        "output": {"name": "descriptor", "length": 512, "normalization": "external L2"},
        "evidence": {"purpose": "conversion-parity-and-local-runtime",
                     "syntheticCaseCount": len(synthetic_names), "providedCropCount": extra_count,
                     "recognitionCalibrationValidated": False, "passivePADValidated": False,
                     "automaticUnlockValidated": False},
        "parity": {"passed": all(item["passed"] for item in comparison),
                   "minimumRequiredCosine": minimum_cosine,
                   "minimumMeasuredCosine": min(item["cosine"] for item in comparison),
                   "maximumPairwiseCosineDifference": pair_error, "cases": comparison},
        "runtime": {"computeUnits": args.compute_units, "coreMLLoadMilliseconds": load_ms,
                    "loadMeasurement": "first MLModel load in this process; persistent compilation-cache state uncontrolled",
                    "coreMLFirstPredictionMilliseconds": first_ms,
                    "warmInference": stats(timings), "referenceONNXLoadMilliseconds": reference_load_ms,
                    "referenceONNXInference": stats(reference_ms),
                    "processPeakResidentBytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                    "peakMemoryIncludesBothRuntimes": True,
                    "warmP95BudgetMilliseconds": 200, "warmP95BudgetPassed": np.percentile(timings, 95) <= 200},
        "machine": {"system": platform.platform(), "architecture": platform.machine(),
                    "processor": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
                    "physicalMemoryBytes": int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip())},
        "dependencies": {name: importlib.metadata.version(name)
                         for name in ("coremltools", "numpy", "onnx", "onnxruntime", "pillow")},
    }
    # Convert NumPy's bool scalar before JSON encoding.
    report["runtime"]["warmP95BudgetPassed"] = bool(report["runtime"]["warmP95BudgetPassed"])
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    if args.fixture:
        args.fixture.write_text(json.dumps({"modelIdentifier": auraface.MODEL_IDENTIFIER,
                                           "sourceSHA256": source_hash, "samples": synthetic_vectors}, indent=2) + "\n")
    print(json.dumps({"report": str(args.report), "precision": precision,
                      "parityPassed": report["parity"]["passed"],
                      "minimumCosine": report["parity"]["minimumMeasuredCosine"],
                      "runtime": report["runtime"]}, indent=2))
    return 0 if report["parity"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
