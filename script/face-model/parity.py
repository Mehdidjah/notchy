"""Check a converted Face Check model against dlib itself, and write the Swift test fixture.

    python3 -I script/face-model/parity.py \
        --dat /path/to/dlib_face_recognition_resnet_model_v1.dat \
        --package Sources/Notchy/Features/FaceCheck/Model/FaceDescriptor.mlpackage \
        [--package other.mlpackage ...] [--fixture Tests/NotchyTests/Fixtures/FaceCheckDescriptors.json]

Needs the `dlib` Python package (pip install dlib) for the reference descriptors, plus
coremltools, numpy and Pillow. The test chips are synthetic and integer-exact, so the Swift
test (FaceCheckEmbedderTests) can rebuild exactly the same pixels from the fixture's
generator name and seed; no photos of people are involved.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402

import dlibnet  # noqa: E402

SIZE = dlibnet.CHIP_SIZE
MIN_COSINE = 0.999

# ---------------------------------------------------------------------------------------
# Synthetic chips. Integer arithmetic only, so Swift reproduces them bit for bit.


def _xorshift32(state: int) -> int:
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= state >> 17
    state ^= (state << 5) & 0xFFFFFFFF
    return state


def _noise(seed: int) -> np.ndarray:
    state = seed
    values = np.empty(SIZE * SIZE * 3, dtype=np.uint8)
    for i in range(values.size):
        state = _xorshift32(state)
        values[i] = state >> 24
    return values.reshape(SIZE, SIZE, 3)


def _gradient(_: int) -> np.ndarray:
    r, c = np.mgrid[0:SIZE, 0:SIZE]
    return np.stack([r * 255 // 149, c * 255 // 149, (r + c) * 255 // 298], axis=-1).astype(np.uint8)


def _rings(_: int) -> np.ndarray:
    r, c = np.mgrid[0:SIZE, 0:SIZE]
    d2 = (r - 75) ** 2 + (c - 75) ** 2
    red = 255 - np.minimum(255, d2 * 255 // 11250)
    green = (d2 // 23) % 256
    blue = (r * c // 89) % 256
    return np.stack([red, green, blue], axis=-1).astype(np.uint8)


def _blocks(seed: int) -> np.ndarray:
    state = seed
    out = np.empty((SIZE, SIZE, 3), dtype=np.uint8)
    for row in range(15):
        for col in range(15):
            colour = []
            for _ in range(3):
                state = _xorshift32(state)
                colour.append(state >> 24)
            out[row * 10:(row + 1) * 10, col * 10:(col + 1) * 10] = colour
    return out


def _inside(r, c, cy, cx, ry, rx):
    return (c - cx) ** 2 * ry * ry + (r - cy) ** 2 * rx * rx <= rx * rx * ry * ry


def _cartoon(_: int) -> np.ndarray:
    r, c = np.mgrid[0:SIZE, 0:SIZE]
    out = np.empty((SIZE, SIZE, 3), dtype=np.int64)
    out[:] = (92, 96, 108)
    shapes = [  # centre row, centre col, radius rows, radius cols, colour; later ones on top
        (62, 75, 52, 50, (58, 40, 30)),     # hair
        (82, 75, 58, 46, (226, 178, 146)),  # face
        (64, 56, 5, 10, (245, 245, 240)),   # eye whites
        (64, 94, 5, 10, (245, 245, 240)),
        (64, 56, 4, 4, (52, 38, 32)),       # irises
        (64, 94, 4, 4, (52, 38, 32)),
        (54, 56, 2, 11, (70, 50, 38)),      # brows
        (54, 94, 2, 11, (70, 50, 38)),
        (88, 75, 11, 5, (206, 152, 122)),   # nose
        (110, 75, 5, 17, (164, 72, 70)),    # mouth
    ]
    for cy, cx, ry, rx, colour in shapes:
        out[_inside(r, c, cy, cx, ry, rx)] = colour
    return out.astype(np.uint8)


def _cartoon_noisy(seed: int) -> np.ndarray:
    base = _cartoon(seed).astype(np.int64).reshape(-1)
    state = seed
    for i in range(base.size):
        state = _xorshift32(state)
        base[i] += (state >> 24) % 25 - 12
    return np.clip(base, 0, 255).astype(np.uint8).reshape(SIZE, SIZE, 3)


GENERATORS = {
    "noise": _noise,
    "gradient": _gradient,
    "rings": _rings,
    "blocks": _blocks,
    "cartoon": _cartoon,
    "cartoonNoisy": _cartoon_noisy,
}

SAMPLES = [
    ("noise", 1), ("noise", 2), ("noise", 3),
    ("gradient", 0), ("rings", 0), ("blocks", 4),
    ("cartoon", 0), ("cartoonNoisy", 5),
]


def chip(generator: str, seed: int) -> np.ndarray:
    return GENERATORS[generator](seed)


def fnv1a32(data: bytes) -> int:
    """Checksum of the RGB bytes, so the Swift test can confirm it rebuilt the same chip."""
    value = 0x811C9DC5
    for byte in data:
        value = ((value ^ byte) * 0x01000193) & 0xFFFFFFFF
    return value


# ---------------------------------------------------------------------------------------


def compare(reference: np.ndarray, candidate: np.ndarray) -> dict:
    reference = reference.astype(np.float64)
    candidate = candidate.astype(np.float64)
    return {
        "max_abs": float(np.abs(reference - candidate).max()),
        "cosine": float(reference @ candidate / (np.linalg.norm(reference) * np.linalg.norm(candidate))),
        "distance": float(np.linalg.norm(reference - candidate)),
        "norm_ratio": float(np.linalg.norm(candidate) / np.linalg.norm(reference)),
    }


def coreml_descriptor(model, image_rgb: np.ndarray) -> np.ndarray:
    from PIL import Image

    output = model.predict({"image": Image.fromarray(image_rgb, mode="RGB")})
    return np.asarray(output["descriptor"], dtype=np.float64).reshape(-1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare converted face models against dlib.")
    parser.add_argument("--dat", required=True)
    parser.add_argument("--package", action="append", default=[], help=".mlpackage to check (repeatable)")
    parser.add_argument("--fixture", help="write the Swift test fixture JSON here")
    parser.add_argument("--neural-engine", action="store_true",
                        help="also run each package with CPU + Neural Engine")
    args = parser.parse_args()

    import dlib
    import coremltools as ct

    recogniser = dlib.face_recognition_model_v1(args.dat)
    net = dlibnet.load(args.dat)

    chips = {f"{g}-{s}": chip(g, s) for g, s in SAMPLES}
    reference = {name: np.array(recogniser.compute_face_descriptor(image), dtype=np.float64)
                 for name, image in chips.items()}

    runtimes = {"numpy-fp64": lambda image: dlibnet.forward(net, image, np.float64)}
    for package in args.package:
        units = [("cpu", ct.ComputeUnit.CPU_ONLY)]
        if args.neural_engine:
            units.append(("cpu+ane", ct.ComputeUnit.CPU_AND_NE))
        for unit_name, unit in units:
            model = ct.models.MLModel(package, compute_units=unit)
            precision = model.user_defined_metadata.get("notchy.faceModel.precision", "?")
            label = f"coreml {os.path.basename(package)} [{precision}, {unit_name}]"
            runtimes[label] = (lambda m: lambda image: coreml_descriptor(m, image))(model)

    print(f"dlib {dlib.__version__}; reference descriptor norms: "
          + ", ".join(f"{name} {np.linalg.norm(v):.4f}" for name, v in reference.items()))
    failures = 0
    for runtime_name, run in runtimes.items():
        print(f"\n{runtime_name}")
        print(f"  {'sample':<16}{'max |diff|':>12}{'cosine':>14}{'distance':>12}{'norm ratio':>12}")
        for name, image in chips.items():
            stats = compare(reference[name], run(image))
            ok = stats["cosine"] >= MIN_COSINE and abs(stats["norm_ratio"] - 1) < 0.01
            failures += 0 if ok else 1
            print(f"  {name:<16}{stats['max_abs']:>12.3e}{stats['cosine']:>14.8f}"
                  f"{stats['distance']:>12.3e}{stats['norm_ratio']:>12.6f}{'' if ok else '  FAIL'}")

    if args.fixture:
        with open(args.dat, "rb") as handle:
            source_sha256 = hashlib.sha256(handle.read()).hexdigest()
        header = {
            "about": "dlib 128-d face descriptors for synthetic 150x150 chips; regenerate with "
                     "script/face-model/parity.py",
            "dlibVersion": dlib.__version__,
            "sourceSHA256": source_sha256,
        }
        # One sample per line keeps the file small and diffs readable.
        lines = [json.dumps(header)[:-1] + ', "samples": [']
        for index, (g, s) in enumerate(SAMPLES):
            sample = {"generator": g, "seed": s,
                      "rgbChecksum": fnv1a32(chips[f"{g}-{s}"].tobytes()),
                      "descriptor": [float(f"{v:.7g}") for v in reference[f"{g}-{s}"]]}
            comma = "," if index < len(SAMPLES) - 1 else ""
            lines.append(" " + json.dumps(sample, separators=(",", ":")) + comma)
        lines.append("]}")
        os.makedirs(os.path.dirname(os.path.abspath(args.fixture)), exist_ok=True)
        with open(args.fixture, "w") as handle:
            handle.write("\n".join(lines) + "\n")
        json.load(open(args.fixture))  # must round-trip
        print(f"\nwrote {args.fixture} ({os.path.getsize(args.fixture):,} bytes)")

    print(f"\n{'all samples pass' if failures == 0 else f'{failures} sample(s) below the bar'} "
          f"(cosine >= {MIN_COSINE}, norms within 1%)")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
