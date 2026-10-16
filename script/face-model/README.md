# Face Check model tools

These scripts turn dlib's public-domain face-recognition network
(`dlib_face_recognition_resnet_model_v1`) into the Core ML model that Face Check ships, and
check it against dlib. Origin, licence and training-data notes are in
`Sources/Notchy/Features/FaceCheck/Model/MODEL-LICENSE.md`.

| File | What it does |
|---|---|
| `dlibnet.py` | Reads dlib's `.dat` network file with numpy and runs a reference forward pass. |
| `convert.py` | Builds a Core ML ML Program (macOS 14+) from those weights with coremltools' MIL builder. No deep-learning framework needed. |
| `parity.py` | Compares dlib, the numpy reference and Core ML packages on synthetic chips, and writes `Tests/NotchyTests/Fixtures/FaceCheckDescriptors.json`. |

## What is checked in, and how it ships

- `Sources/Notchy/Features/FaceCheck/Model/FaceDescriptor.mlpackage` is the **float16**
  conversion (11.2 MB of weights). It is checked in, so building Notchy needs no Python, no
  download and no conversion. Package.swift excludes the folder from the target.
- `script/build_and_run.sh` compiles it with `xcrun coremlcompiler` into
  `Notchy.app/Contents/Resources/FaceDescriptor.mlmodelc` and copies the licence note next to
  it. `FaceEmbedder` loads it from there with `Bundle.main`.
- The unit tests compile the `.mlpackage` at test time (`MLModel.compileModel(at:)`) and compare
  the results with dlib's descriptors in the fixture.

The model takes a 150x150 RGB image: a face chip aligned the way dlib's
`get_face_chip_details(shape, 150, 0.25)` aligns it. Its input step does dlib's preprocessing,
`(pixel - mean) / 256`, with channel means 122.782, 117.001 and 104.298 read from the file. It
returns the 128-number descriptor `descriptor` (Float32 `[1, 128]`), not normalised. dlib's
same-person radius is 0.6 (Euclidean).

## Regenerating

macOS with Xcode, and any Python 3. Keep the download in its own directory, and run Python
with `-I` so nothing next to the download can be imported.

```sh
python3 -m venv /tmp/face-venv
/tmp/face-venv/bin/python -I -m pip install --pre -r script/face-model/requirements.txt
# dlib builds with cmake. If linking fails with "tapi error: unknown architecture", point
# the build at Xcode's SDK:
#   SDKROOT=$(xcrun --sdk macosx --show-sdk-path) /tmp/face-venv/bin/python -I -m pip install dlib==20.0.1

mkdir -p /tmp/face-download && cd /tmp/face-download
curl -LO http://dlib.net/files/dlib_face_recognition_resnet_model_v1.dat.bz2
shasum -a 256 dlib_face_recognition_resnet_model_v1.dat.bz2   # abb1f610...b11553a
bunzip2 -k dlib_face_recognition_resnet_model_v1.dat.bz2        # .dat: 55533b28...719da30
cd -

/tmp/face-venv/bin/python -I script/face-model/convert.py \
  --dat /tmp/face-download/dlib_face_recognition_resnet_model_v1.dat \
  --out Sources/Notchy/Features/FaceCheck/Model/FaceDescriptor.mlpackage --precision fp16

/tmp/face-venv/bin/python -I script/face-model/parity.py \
  --dat /tmp/face-download/dlib_face_recognition_resnet_model_v1.dat \
  --package Sources/Notchy/Features/FaceCheck/Model/FaceDescriptor.mlpackage --neural-engine \
  --fixture Tests/NotchyTests/Fixtures/FaceCheckDescriptors.json

swift test --filter FaceCheck
```

`convert.py` refuses a `.dat` whose SHA-256 differs from the one above unless you pass
`--allow-unknown-source`. Conversion is deterministic: `weight.bin` should come out with
SHA-256 `20c052b69c8696378139267ec842964e19ae3fb23294ff1279c3c9265f6d27a2`. Only
`Manifest.json` (random item IDs) and the conversion date in the metadata change between runs.

## Parity (2026-10-16, dlib 20.0.1, coremltools 9.1.dev1, macOS 27 on Apple silicon)

Eight synthetic chips: three noise images, a gradient, rings, colour blocks, a cartoon face and
a noisy cartoon face. Each candidate is compared with `dlib.face_recognition_model_v1(...)
.compute_face_descriptor(chip)`. Worst case over the eight:

| Runtime | max abs diff | min cosine | max distance | norm ratio |
|---|---|---|---|---|
| numpy reference (float64) | 4.0e-7 | 1.00000000 | 1.0e-6 | 1.000000 |
| Core ML float32, CPU | 3.5e-7 | 1.00000000 | 1.6e-6 | 1.000000 |
| Core ML float16, CPU | 2.5e-3 | 0.99998038 | 8.3e-3 | 0.9989-1.0008 |
| Core ML float16, CPU + Neural Engine | 9.2e-4 | 0.99999780 | 2.9e-3 | 1.0004-1.0008 |

The pass bar is cosine >= 0.999 with norms within 1%. The worst float16 distance (0.0083) is
1.4% of the 0.6 same-person radius. The closest pair of different test chips sits 0.163
apart, so the check can tell the chips apart. The Swift test
(`Tests/NotchyTests/FaceCheckEmbedderTests.swift`) repeats this through `FaceEmbedder` and
gets the same numbers.

## How the `.dat` file is laid out

dlib writes a network by walking its C++ template type and stores no layer list. Each wrapper
writes its version number, then the network beneath it, then its own record. So the file is:

1. the loss layer's version and record (`loss_metric_2`, margin 0.04, distance threshold 0.6);
2. one version number per wrapper, from the output end down to the input;
3. the input layer (`input_rgb_image_sized`: channel means, 150, 150);
4. each layer's record from the input end up (`con_*`, `affine_*`, `relu_*`, `max_pool_2`,
   `avg_pool_2`, `add_prev_`, `fc_*`), each followed by flags and empty scratch tensors.

Integers are a length byte (bit 7 = sign) plus little-endian magnitude bytes. Reals are an
integer mantissa and power-of-two exponent. Strings are length-prefixed. Tensors are a version
number, four dimensions and raw little-endian float32 values. `dlibnet.FORWARD_LAYOUT` spells
out the 29-convolution network, and the reader checks each record against it and requires the
file to end exactly where the last record does.

Two details matter for a faithful port. Down-sampling residual units add a 2x2 average-pooled
shortcut to a stride-2 convolution branch whose shape can differ; dlib adds them as if the
smaller one had zeros appended along each axis, which the converter reproduces with `pad`. And
the strided 3x3 convolutions use no padding, unlike the stride-1 ones.
